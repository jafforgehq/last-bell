## The patrol's night meter (PATROL4, scripts/town/patrol.gd): plays the first attack night of a seed headless at the game's own 30 Hz, the avatar's hands off, the crew on patrol, and
## measures what a person would SEE of it: people on top of each other, walking through each other, standing about in the open, how long a patroller takes from "a dead one is in
## reach" to the first shot, how long the dead claw at a fence before somebody can shoot them, anybody outside the lot, jitter (turning back on themselves, switching between two places).
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/patrol_night.gd -- --seeds=1,5,9 [--people=3] [--weather=storm] [--fall-at=120] [--ammo-out-at=150] [--stage=night] [--slots=built]
##                                                                   [--timeline=0] [--hz=30] [--blocks=6] [--out=/path/file.txt] [--case=night|day|orders]
##
##   --people=3       the crew besides the avatar (the stage has two; the rest are made up at the avatar's side)
##   --weather=       the first night's sky: storm, rain, drizzle, clear
##   --fall-at=S      S seconds into the night a fence section falls (the one the dead are clawing at, else the nearest to the first of them)
##   --ammo-out-at=S  from S seconds in the stores' ammunition is nil (the guns are the butt)
##   --ammo=N         the stores' ammunition at the start (default: as the stage leaves it, 40 and nobody at the bench)
##   --verbose=1      one line for each reaction; 2 also one for each time two people come within 0.9 tiles
##   --timeline=N     print one line of the crew's places and modes every N seconds
##   --case=day       the day's rules (nobody patrols with no dead near and no call; the call to arms; the dead coming by day), --case=orders: orders against patrol (a scavenge order, a
##                    builder at night, the downed, the avatar)
## One line per seed: `PATROL_NIGHT seed=...`, then a SUMMARY.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const PerimeterStage := preload("res://scripts/town/perimeter_stage.gd")

var o := {"seeds": "1", "people": 3, "weather": "", "fall-at": -1.0, "ammo-out-at": -1.0, "stage": "night", "slots": "built", "timeline": 0.0, "hz": 30.0, "blocks": 6, "out": "", "case": "night", "max-s": 520.0, "verbose": 0, "ammo": -1.0}
var _lines: Array = []


func _initialize() -> void:
	_main.call_deferred()


func _read_opts() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		if kv.size() == 2 and o.has(kv[0]):
			if typeof(o[kv[0]]) == TYPE_STRING:
				o[kv[0]] = kv[1]
			elif typeof(o[kv[0]]) == TYPE_INT:
				o[kv[0]] = kv[1].to_int()
			else:
				o[kv[0]] = kv[1].to_float()
		elif kv.size() == 1 and o.has(kv[0]):
			o[kv[0]] = 1


static func _seeds(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var t := String(part).strip_edges()
		if t.contains(".."):
			var ends := t.split("..", false)
			for v in range(int(ends[0]), int(ends[1]) + 1):
				out.append(v)
		elif t.is_valid_int():
			out.append(t.to_int())
	return out


func _say(text: String) -> void:
	print(text)
	_lines.append(text)


func _main() -> void:
	_read_opts()
	if String(o.case) == "audit":
		_audit()
		if String(o.out) != "":
			var fa := FileAccess.open(String(o.out), FileAccess.WRITE)
			if fa != null:
				fa.store_string("\n".join(_lines) + "\n")
		quit(0)
		return
	var rows: Array = []
	for sd in _seeds(String(o.seeds)):
		var row: Dictionary
		match String(o.case):
			"day":
				row = _case_day(int(sd))
			"orders":
				row = _case_orders(int(sd))
			_:
				row = _night(int(sd))
		rows.append(row)
	if String(o.case) == "night":
		_summary(rows)
	if String(o.out) != "":
		var f := FileAccess.open(String(o.out), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_lines) + "\n")
	quit(0)


# ---------------------------------------------------------------------- set up --

func _setup(seed_value: int) -> Dictionary:
	var g := Helpers.town_game(seed_value, {"blocks": int(o.blocks)})
	var sim = g.sim
	OneHouse.begin(sim, -1, seed_value)
	if not OneHouse.stage_to(sim, String(o.stage)):
		_say("PATROL_NIGHT seed=%d stage refused" % seed_value)
		return {}
	if String(o.slots) != "":
		PerimeterStage.apply(sim, String(o.slots))
	if float(o.ammo) >= 0.0:
		sim.stock["ammo"] = float(o.ammo)    # (-1: the stores as the stage leaves them, which is what a night with nobody at the bench is)
	if String(o.weather) != "":
		sim.skies.force_first_night(String(o.weather))
	var guard := 0
	while _crew(sim).size() < int(o.people) and guard < 8:
		sim.scenario._stage_join(1)
		guard += 1
	return g


static func _crew(sim) -> Array:
	var out: Array = []
	for p in sim.people:
		if not p.player and not (p.dead or p.turned):
			out.append(p)
	return out


# ----------------------------------------------------------------------- night --

func _night(seed_value: int) -> Dictionary:
	var g := _setup(seed_value)
	if g.is_empty():
		return {}
	var sim = g.sim
	var pat = sim.patrol
	var hz := float(o.hz)
	var dt := 1.0 / hz
	pat.update(0.0)
	pat.points()    # (makes the loop)
	var lot: Rect2 = pat.lot()
	var crew := _crew(sim)
	_say("PATROL_NIGHT seed=%d start day %d %.1f h phase %s crew %d  lot %s loop %d pts %.0f tiles" % [seed_value, int(sim.day), float(sim.hour), String(sim.phase), crew.size(), str(lot), pat.points().size(), pat.loop_length()])
	var m := {"seed": seed_value, "t": 0.0, "manned_s": 0.0, "close05": 0.0, "close09": 0.0, "passes": 0, "idle_s": 0.0, "hold_nt_s": 0.0, "out_s": 0.0, "unopposed_s": 0.0, "claw_s": 0.0, "noammo_s": 0.0, "ammo_out_t": -1.0,
		"react": [], "no_shot": 0, "cover": [], "flips": 0, "switches": 0, "shots": 0, "kills": 0, "clump_s": 0.0, "walk_s": 0.0, "quiet_gap": []}
	var prev := {}       # id -> Vector2 last position
	var hist := {}       # id -> Array of Vector2 (last 1 s)
	var still := {}      # id -> seconds standing in mode walk
	var has_since := {}  # id -> time since `_find_target` has been non-null (or -1)
	var has_info := {}
	var no_since := {}   # id -> seconds the target has been null
	var shots_last := {}
	var last_mode := {}
	var overlap_pair := {}
	var near_pair := {}
	var flip_t := {}
	var first_attack := {}
	var hold_nt := {}
	var t := 0.0
	var started := false
	var fell := false
	var next_log := 0.0
	var t_manned := -1.0
	var max_s := float(o["max-s"])
	var steps := 0
	var walked_night := false
	while t < max_s and sim.over == "":
		sim.update(dt)
		sim.events.clear()
		t += dt
		steps += 1
		var manned: bool = sim.posts_manned()
		if manned and t_manned < 0.0:
			t_manned = t
		if String(sim.phase) == "night" or String(sim.phase) == "dusk" and sim.bell_rung:
			walked_night = true
		if walked_night and String(sim.phase) == "day":
			break
		if float(o["ammo-out-at"]) >= 0.0 and t_manned >= 0.0 and t - t_manned >= float(o["ammo-out-at"]):
			sim.stock["ammo"] = 0.0
		if not manned:
			continue
		m.manned_s += dt
		var now_t := t
		crew = _crew(sim)
		var snap: Dictionary = {}
		for e in pat.snapshot():
			snap[String(e.id)] = e
		var live: Array = []
		for p in sim.people:
			if not (p.dead or p.turned) and p.away == null and not p.downed:
				live.append(p)
		# the people on top of each other
		for i in live.size():
			for j in range(i + 1, live.size()):
				var a = live[i]
				var b = live[j]
				var d := Vector2(a.x - b.x, a.y - b.y).length()
				var key := String(a.id) + "|" + String(b.id)
				if String(a.activity).begins_with("Bandag") or String(b.activity).begins_with("Bandag") or String(a.activity).begins_with("Treat") or String(b.activity).begins_with("Treat"):
					continue    # (a medic at a patient is meant to stand by them)
				if d < 0.5:
					m.close05 += dt
				if d < 0.9:
					m.close09 += dt
					if int(o.verbose) >= 2 and not near_pair.has(key):
						near_pair[key] = true
						var ma: String = String(snap[String(a.id)].mode) if snap.has(String(a.id)) else "-" + String(a.activity).left(14)
						var mb: String = String(snap[String(b.id)].mode) if snap.has(String(b.id)) else "-" + String(b.activity).left(14)
						_say("   close t=%.1f d=%.2f  %s(%.1f,%.1f) %s %s  |  %s(%.1f,%.1f) %s %s" % [t, d, String(a.first), a.x, a.y, ma, "mv" if a.moving else "st", String(b.first), b.x, b.y, mb, "mv" if b.moving else "st"])
				elif d > 1.3:
					near_pair.erase(key)
				if d < 0.55:
					if not overlap_pair.has(key):
						overlap_pair[key] = true
						if int(o.verbose) >= 2:
							var ma2: String = String(snap[String(a.id)].mode) if snap.has(String(a.id)) else "-" + String(a.activity).left(14)
							var mb2: String = String(snap[String(b.id)].mode) if snap.has(String(b.id)) else "-" + String(b.activity).left(14)
							_say("   ON TOP t=%.1f d=%.2f  %s(%.1f,%.1f) %s %s  |  %s(%.1f,%.1f) %s %s" % [t, d, String(a.first), a.x, a.y, ma2, "mv" if a.moving else "st", String(b.first), b.x, b.y, mb2, "mv" if b.moving else "st"])
						var va: Vector2 = Vector2(a.x, a.y) - Vector2(prev.get(String(a.id), Vector2(a.x, a.y)))
						var vb: Vector2 = Vector2(b.x, b.y) - Vector2(prev.get(String(b.id), Vector2(b.x, b.y)))
						if va.length() > 0.004 and vb.length() > 0.004 and va.dot(vb) < 0.0:
							m.passes += 1
				elif d > 0.9:
					overlap_pair.erase(key)
		var patrollers: Array = []
		for p in crew:
			var e = snap.get(String(p.id))
			if e != null and not p.downed and p.away == null:
				patrollers.append(p)
		m.walk_s += dt * float(patrollers.size())
		# the clump of patrollers: two within 2 tiles for a stretch while both are walking
		for i in patrollers.size():
			var pi = patrollers[i]
			var ei: Dictionary = snap[String(pi.id)]
			var id := String(pi.id)
			var pos := Vector2(pi.x, pi.y)
			var mode := String(ei.mode)
			if not lot.has_point(pos):
				m.out_s += dt
			# switches between places (a sent one let go and sent again)
			if last_mode.has(id) and String(last_mode[id]) != mode and ((String(last_mode[id]) == "hold" and mode == "walk") or (String(last_mode[id]) == "go" and mode == "walk")):
				m.switches += 1
			last_mode[id] = mode
			# standing about
			var has_target = sim._find_target(pi) != null and sim.gun_of(pi) != sim.BUTT
			if not pi.moving and mode == "walk":
				still[id] = float(still.get(id, 0.0)) + dt
				if float(still[id]) > 0.6 and not has_target:
					m.idle_s += dt
			else:
				still[id] = 0.0
			if (mode == "hold" or mode == "engaged") and not has_target:
				hold_nt[id] = float(hold_nt.get(id, 0.0)) + dt
				if float(hold_nt[id]) > 2.0:
					m.hold_nt_s += dt
					if int(o.verbose) >= 2 and float(hold_nt[id]) < 2.0 + dt:
						var near_dead: Array = []
						for z in sim.zombies:
							var zd := Vector2(z.x, z.y).distance_to(pos)
							if zd < 24.0 and z.state != "dead" and z.state != "dying":
								near_dead.append("%s@%.0f(%s)" % [String(z.kind).left(1), zd, String(z.state)])
						near_dead.sort()
						_say("   HOLD-NO-TARGET t=%.1f %s (%.1f,%.1f) %s reach %.1f press %.2f | %s" % [now_t, String(pi.first), pi.x, pi.y, mode, sim.reach_of(sim.gun_of(pi), pi), float(ei.pressure), " ".join(near_dead.slice(0, 10))])
			else:
				hold_nt[id] = 0.0
			# the reaction: a dead one comes within reach (after a second without one) to the first shot
			if has_target:
				if float(no_since.get(id, 99.0)) >= 1.0 and not has_since.has(id) and pi.reloading <= 0.0:
					has_since[id] = now_t
					has_info[id] = "%s mode=%s moving=%s cd=%.2f mag=%d" % [String(pi.first), mode, str(pi.moving), float(pi.cooldown), int(pi.mag)]
				no_since[id] = 0.0
			else:
				no_since[id] = float(no_since.get(id, 99.0)) + dt
				if has_since.has(id):
					if now_t - float(has_since[id]) > 0.0:
						m.no_shot += 1
					has_since.erase(id)
			var sh := int(pi.stats.shots)
			if has_since.has(id) and sh > int(shots_last.get(id, sh)):
				m.react.append(now_t - float(has_since[id]))
				if int(o.verbose) > 0:
					_say("   react %.2f s: %s at t=%.1f" % [now_t - float(has_since[id]), String(has_info.get(id, "")), now_t])
				has_since.erase(id)
			shots_last[id] = sh
			# turning back on themselves while they walk
			var h: Array = hist.get(id, [])
			h.append(pos)
			if h.size() > 31:
				h.pop_front()
			hist[id] = h
			if h.size() >= 31 and pi.moving and now_t - float(flip_t.get(id, -9.0)) > 1.5:
				var d1: Vector2 = h[15] - h[0]
				var d2: Vector2 = h[30] - h[15]
				if d1.length() > 0.25 and d2.length() > 0.25 and d1.normalized().dot(d2.normalized()) < -0.5:
					m.flips += 1
					flip_t[id] = now_t
					if int(o.verbose) >= 2:
						_say("   FLIP t=%.1f %s (%.1f,%.1f) %s tgt %d  was heading (%.2f,%.2f) now (%.2f,%.2f)" % [now_t, String(pi.first), pi.x, pi.y, mode, int(ei.tgt), d1.x, d1.y, d2.x, d2.y])
			for j in range(i + 1, patrollers.size()):
				var pj = patrollers[j]
				if Vector2(pi.x - pj.x, pi.y - pj.y).length() < 2.0 and mode == "walk" and String(snap[String(pj.id)].mode) == "walk":
					m.clump_s += dt * 0.5
		for p in live:
			prev[String(p.id)] = Vector2(p.x, p.y)
		# the dead at the fence: shot or not, and how long until the first shooter is in reach
		var shooters: Array = []
		for p in live:
			if not p.player:
				shooters.append(p)
		for z in sim.zombies:
			if z.state != "attack" and z.state != "breach":
				first_attack.erase(z)
				continue
			var zp := Vector2(z.x, z.y)
			var covered := false
			for p in shooters:
				if Vector2(p.x, p.y).distance_to(zp) <= sim.reach_of(p.gun, p):    # (the gun's own reach: with the stores empty the guns are the butt, and that time is `noammo_s`)
					covered = true
					break
			m.claw_s += dt
			if float(sim.stock.ammo) < float(sim.SHOT_COST):
				m.noammo_s += dt
				if float(m.ammo_out_t) < 0.0:
					m.ammo_out_t = t
			elif not covered:
				m.unopposed_s += dt
				if int(o.verbose) >= 3 and int(floor(t * 2.0)) % 20 == 0 and int(floor(t * 2.0 - dt * 2.0)) % 20 != 0:
					var parts: Array = []
					for p in shooters:
						var e = snap.get(String(p.id))
						parts.append("%s(%.1f,%.1f) %s d=%.1f reach %.1f" % [String(p.first).left(3), p.x, p.y, String(e.mode) if e != null else "-" + String(p.activity).left(12), Vector2(p.x, p.y).distance_to(zp), sim.reach_of(p.gun, p)])
					_say("   unopposed t=%.0f %s z(%.1f,%.1f) %s %s | %s" % [t, String(z.kind), z.x, z.y, String(z.state), String(sim.weapon_name(null)) if false else "", " | ".join(parts)])
			if not first_attack.has(z):
				first_attack[z] = {"t": now_t, "done": false}
			elif not bool(first_attack[z].done) and covered:
				first_attack[z].done = true
				m.cover.append(now_t - float(first_attack[z].t))
		# even spread when it is quiet
		var arcs: Array = []
		var dead_near := false
		for z in sim.zombies:
			if (z.state == "attack" or z.state == "breach" or z.state == "approach") and z.x > lot.position.x - 14.0 and z.x < lot.end.x + 14.0 and z.y > lot.position.y - 14.0 and z.y < lot.end.y + 14.0:
				dead_near = true
				break
		if not dead_near and patrollers.size() >= 2:
			for p in patrollers:
				arcs.append(float(pat._cum[pat.nearest(Vector2(p.x, p.y))]))
			arcs.sort()
			var mn := 1.0e9
			for k in arcs.size():
				mn = minf(mn, fposmod(float(arcs[(k + 1) % arcs.size()]) - float(arcs[k]), pat.loop_length()))
			m.quiet_gap.append(mn)
		# the section that falls
		if not fell and float(o["fall-at"]) >= 0.0 and t_manned >= 0.0 and t - t_manned >= float(o["fall-at"]):
			var seg = _pick_section(sim, lot)
			if seg != null:
				seg.hp = 0.0
				sim._segment_state(seg)
				fell = true
				_say("  t=%.0f: %s falls (%s)" % [t, String(seg.name), str(seg.center)])
		if float(o.timeline) > 0.0 and t >= next_log:
			next_log += float(o.timeline)
			_say(_line(sim, pat, t, crew, snap))
	m.t = t
	m.kills = int(sim.kills)
	var shots := 0
	for p in _crew(sim):
		shots += int(p.stats.shots)
	m.shots = shots
	m["held"] = sim.over == ""
	m["end_hour"] = float(sim.hour)
	m["cost_ms_s"] = (float(pat.usec_goal) + float(pat.usec_replan) + float(pat.get("usec_steer") if pat.get("usec_steer") != null else 0)) / 1000.0 / maxf(float(m.manned_s), 1.0)
	if int(o.verbose) >= 1:
		_say("   cost: goal_for %.1f us x %d, replan %.0f us x %d, steer %.1f us x %d" % [float(pat.usec_goal) / maxf(float(pat.calls_goal), 1.0), int(pat.calls_goal), float(pat.usec_replan) / maxf(float(pat.calls_replan), 1.0), int(pat.calls_replan),
			float(pat.get("usec_steer")) / maxf(float(pat.get("calls_steer")), 1.0), int(pat.get("calls_steer"))])
	m["min_hp"] = _min_seg(sim)
	_row_line(m)
	g.world.free()
	return m


func _min_seg(sim) -> float:
	var worst := 1.0
	for s in sim.segments:
		if int(s.id) >= 100 or String(s.kind) == "door":
			continue
		worst = minf(worst, float(s.hp) / maxf(float(s.max_hp), 1.0))
	return worst


func _pick_section(sim, lot: Rect2):
	var best = null
	var best_n := -1
	for seg in sim.segments:
		if int(seg.id) >= 100 or String(seg.kind) == "door" or int(seg.state) == 3:
			continue
		var n := 0
		for z in sim.zombies:
			if (z.state == "attack" or z.state == "breach") and Vector2(z.x, z.y).distance_to(seg.center) < 5.0:
				n += 1
		if n > best_n:
			best_n = n
			best = seg
	if best_n > 0:
		return best
	# no dead at the fence yet: the section nearest to the first of the dead that come
	var zs = null
	var zd := 1.0e9
	for z in sim.zombies:
		if z.state == "approach" or z.state == "chase":
			var d := Vector2(z.x, z.y).distance_to(lot.get_center())
			if d < zd:
				zd = d
				zs = z
	if zs == null:
		return best
	var bd := 1.0e9
	for seg in sim.segments:
		if int(seg.id) >= 100 or String(seg.kind) == "door" or int(seg.state) == 3:
			continue
		var d := Vector2(zs.x, zs.y).distance_to(seg.center)
		if d < bd:
			bd = d
			best = seg
	return best


func _stat(a: Array) -> String:
	if a.is_empty():
		return "n=0"
	var b := a.duplicate()
	b.sort()
	var sum := 0.0
	for v in b:
		sum += float(v)
	return "n=%d mean %.2f p90 %.2f max %.2f" % [b.size(), sum / float(b.size()), float(b[int(float(b.size() - 1) * 0.9)]), float(b[b.size() - 1])]


func _row_line(m: Dictionary) -> void:
	var qg: Array = m.quiet_gap
	var qmin := 0.0
	for v in qg:
		qmin += float(v)
	qmin = qmin / maxf(float(qg.size()), 1.0)
	_say("PATROL_NIGHT seed=%d ended %.0fs hour %.1f held=%s kills %d shots %d minseg %.2f | on top (<0.5) %.1fs near (<0.9) %.1fs passes %d clump %.0fs | idle %.1fs hold-no-target %.0fs out-of-lot %.1fs | claw %.0fs unopposed %.1fs (stores empty from t=%.0f: %.0fs of it) | flips %d switches %d | quiet-gap mean %.1f" % [
		int(m.seed), float(m.t), float(m.end_hour), str(m.held), int(m.kills), int(m.shots), float(m.min_hp), float(m.close05), float(m.close09), int(m.passes), float(m.clump_s), float(m.idle_s), float(m.hold_nt_s), float(m.out_s), float(m.claw_s), float(m.unopposed_s), float(m.ammo_out_t), float(m.noammo_s), int(m.flips), int(m.switches), qmin])
	_say("    reaction in reach -> first shot: %s (no shot before it left reach: %d) | first shooter in reach after a dead one starts clawing: %s | patrol cost %.2f ms per second of play" % [_stat(m.react), int(m.no_shot), _stat(m.cover), float(m.get("cost_ms_s", 0.0))])


func _summary(rows: Array) -> void:
	var tot := {"close05": 0.0, "close09": 0.0, "passes": 0, "idle_s": 0.0, "hold_nt_s": 0.0, "out_s": 0.0, "unopposed_s": 0.0, "claw_s": 0.0, "noammo_s": 0.0, "flips": 0, "switches": 0, "held": 0, "n": 0, "manned_s": 0.0}
	var react: Array = []
	var cover: Array = []
	for m in rows:
		if m.is_empty():
			continue
		tot.n += 1
		for k in ["close05", "close09", "passes", "idle_s", "hold_nt_s", "out_s", "unopposed_s", "claw_s", "noammo_s", "flips", "switches", "manned_s"]:
			tot[k] += m[k]
		if bool(m.held):
			tot.held += 1
		react.append_array(m.react)
		cover.append_array(m.cover)
	_say("PATROL_NIGHT SUMMARY runs %d held %d | on top %.1fs near %.1fs passes %d | idle %.1fs hold-no-target %.0fs out-of-lot %.1fs | unopposed %.1fs of %.0fs clawing (%.0fs of it with the stores empty) | flips %d (%.2f per manned minute) switches %d" % [
		int(tot.n), int(tot.held), float(tot.close05), float(tot.close09), int(tot.passes), float(tot.idle_s), float(tot.hold_nt_s), float(tot.out_s), float(tot.unopposed_s), float(tot.claw_s), float(tot.noammo_s), int(tot.flips), float(tot.flips) / maxf(float(tot.manned_s) / 60.0, 1.0), int(tot.switches)])
	_say("PATROL_NIGHT SUMMARY reaction %s | cover %s" % [_stat(react), _stat(cover)])


## One line: the time, the dead near the fence, and for each of the crew "name x,y mode".
func _line(sim, pat, t: float, crew: Array, snap: Dictionary) -> String:
	var parts: Array = []
	var dead := 0
	for z in sim.zombies:
		if z.state == "attack" or z.state == "breach" or z.state == "approach":
			dead += 1
	for p in crew:
		var e = snap.get(String(p.id))
		var mode: String = String(e.mode) if e != null else ("-[" + String(p.activity) + "]")
		var i: int = pat.nearest(Vector2(p.x, p.y))
		parts.append("%s %s(%.1f,%.1f) %s%s" % [String(p.first).left(3), String(pat._side[i]), p.x, p.y, mode, " T" if p.target != null else ""])
	return "t=%5.1f h%4.1f dead %2d | %s" % [t, float(sim.hour), dead, " | ".join(parts)]


# ----------------------------------------------------------------------- cases --

func _case_day(seed_value: int) -> Dictionary:
	var g := _setup(seed_value)
	if g.is_empty():
		return {}
	var sim = g.sim
	var pat = sim.patrol
	# a day: ten in the morning, the crew at their jobs
	sim.minutes = 10.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.zombies.clear()
	sim.radio.alarm_on = false
	var dt := 1.0 / 30.0
	for i in 60:
		sim.update(dt)
	sim.events.clear()
	var snap0: Array = pat.snapshot()
	_say("DAY seed=%d 10:00 no call, no dead: posts_manned=%s patrolling=%d (want 0); activities: %s" % [seed_value, str(sim.posts_manned()), snap0.size(), _acts(sim)])
	# the call to arms (L)
	sim.radio.alarm(true)
	for i in 120:
		sim.update(dt)
	var snap1: Array = pat.snapshot()
	_say("DAY seed=%d call to arms: posts_manned=%s patrolling=%d; activities: %s" % [seed_value, str(sim.posts_manned()), snap1.size(), _acts(sim)])
	sim.radio.alarm(false)
	for i in 150:
		sim.update(dt)
	var snap2: Array = pat.snapshot()
	_say("DAY seed=%d stood down: posts_manned=%s patrolling=%d; activities: %s" % [seed_value, str(sim.posts_manned()), snap2.size(), _acts(sim)])
	# the dead come by day: three at the north side, 20 tiles off, approaching
	var lot: Rect2 = pat.lot()
	for k in 3:
		var z = sim.spawn(lot.get_center().x + float(k) * 2.0 - 2.0, lot.position.y - 16.0, "approach")
		z.path = []
	var t := 0.0
	var seen_manned := false
	var seen_patrol := 0
	for i in 600:
		sim.update(dt)
		sim.events.clear()
		t += dt
		if sim.posts_manned():
			seen_manned = true
		seen_patrol = maxi(seen_patrol, pat.snapshot().size())
	_say("DAY seed=%d the dead come by day: posts_manned seen %s, most patrolling %d, dead left %d; activities: %s" % [seed_value, str(seen_manned), seen_patrol, sim.zombies.size(), _acts(sim)])
	g.world.free()
	return {}


func _acts(sim) -> String:
	var parts: Array = []
	for p in sim.people:
		if p.dead or p.turned:
			continue
		parts.append("%s%s: %s [%s]" % [String(p.first), " (avatar)" if p.player else "", String(p.activity), String(sim.jobs.job_of(p))])
	return "; ".join(parts)


func _case_orders(seed_value: int) -> Dictionary:
	var g := _setup(seed_value)
	if g.is_empty():
		return {}
	var sim = g.sim
	var pat = sim.patrol
	var crew := _crew(sim)
	if crew.size() < 3:
		g.world.free()
		return {}
	var tag := "ORDERS seed=%d" % seed_value
	# the call to arms in a quiet evening: everyone but the avatar is on the patrol
	sim.radio.alarm(true)
	_run(sim, 8.0)
	_say("%s: call to arms: patrolling %d of %d crew, the avatar on it: %s" % [tag, pat.snapshot().size(), crew.size(), str(pat.is_walking(sim.avatar.player()))])
	var a = crew[0]
	var b = crew[1]
	var c = crew[2]
	# 1. a scavenge order (the radio's own, a real search of the nearest house): they leave the patrol
	var went: bool = sim.crew_search.stage("%s@near" % String(a.id))
	_run(sim, 4.0)
	_say("%s: %s ordered to search a house (accepted %s): activity '%s', on the patrol %s, stance '%s'" % [tag, String(a.first), str(went), String(a.activity), str(pat.is_walking(a)), String(a.stance)])
	# an order to a spot (order_move) and then "Go back"
	sim.order_move(b, b.x + 3.0, b.y)
	_run(sim, 4.0)
	_say("%s: %s ordered to a spot: activity '%s', on the patrol %s" % [tag, String(b.first), String(b.activity), str(pat.is_walking(b))])
	sim.radio.request(b, "back")
	_run(sim, 6.0)
	_say("%s: %s asked to go back: activity '%s', on the patrol %s" % [tag, String(b.first), String(b.activity), str(pat.is_walking(b))])
	# 2. "To the walls" for a patroller while the posts are manned: back to the walk, no fixed spot
	sim.order_post(c)
	_run(sim, 3.0)
	_say("%s: %s 'to the walls' with the posts manned: order %s, drafted %s, activity '%s', on the patrol %s" % [tag, String(c.first), str(c.order), str(c.drafted), String(c.activity), str(pat.is_walking(c))])
	# 3. somebody downed leaves the patrol; somebody hurt is seen to
	c.downed = true
	_run(sim, 3.0)
	_say("%s: %s downed: on the patrol %s, activity '%s'" % [tag, String(c.first), str(pat.is_walking(c)), String(c.activity)])
	c.downed = false
	b.hp = 25.0
	b.wounds = 2
	b.bleeding = 4.0
	_run(sim, 10.0)
	_say("%s: %s hurt (hp %.0f, bleeding): activity '%s', on the patrol %s | all: %s" % [tag, String(b.first), float(b.hp), String(b.activity), str(pat.is_walking(b)), _acts(sim)])
	# 4. the call stood down on a quiet evening, a builder: the bell has not rung, the crew go back to their jobs
	sim.radio.alarm(false)
	sim.jobs.assign(c, "builders")
	_run(sim, 5.0)
	_say("%s: alarm off before the bell (posts manned %s): %s" % [tag, str(sim.posts_manned()), _acts(sim)])
	# 5. "To the walls" by day stands them at their place of the loop under an order; the call to arms (posts manned) lets the order go and they patrol
	sim.zombies.clear()
	sim.minutes = 10.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.radio.alarm_on = false
	_run(sim, 3.0)
	sim.order_post(a)
	_run(sim, 4.0)
	_say("%s: by day, %s 'to the walls': posts manned %s, order %s, activity '%s'" % [tag, String(a.first), str(sim.posts_manned()), str(a.order), String(a.activity)])
	sim.radio.alarm(true)
	_run(sim, 4.0)
	_say("%s: the call to arms: %s order %s, on the patrol %s, activity '%s'" % [tag, String(a.first), str(a.order), str(pat.is_walking(a)), String(a.activity)])
	g.world.free()
	return {}


func _run(sim, seconds: float) -> void:
	for i in int(seconds * 30.0):
		sim.update(1.0 / 30.0)
		sim.events.clear()


# ----------------------------------------------------------------------- audit --

## `--case=audit --seeds=1..64`: every candidate home of every town (the three the New game offers): is its lot a rectangle, is the ring two tiles inside it a closed loop of open ground
## with no long gaps and no point outside the lot, are the links between the points walkable in a straight line, and what posts the layout makes (towers, fence stretches, a gate).
func _audit() -> void:
	var TownGen := load("res://scripts/town/town_gen.gd")
	var BaseLayout := load("res://scripts/town/base_layout.gd")
	var Patrol := load("res://scripts/town/patrol.gd")
	var sums := {"cands": 0, "rect": 0, "not_rect": 0, "bad_loop": 0, "blocked_links": 0, "max_gap": 0.0, "problems": 0, "towers": 0, "gates": 0, "fence_posts": 0, "min_pts": 999, "maxpts": 0, "short_side": 0}
	for sd in _seeds(String(o.seeds)):
		var town: Dictionary = TownGen.make(int(sd), {"blocks": int(o.blocks)})
		for c in town.candidates:
			var hid := int(c.house)
			var layout: Dictionary = BaseLayout.make(town, hid)
			var grid = BaseLayout._grid(town)
			var h: Dictionary = town.houses[hid]
			var lot: Rect2i = h.lot
			var plot: Rect2i = layout.plot
			sums.cands += 1
			var rect_ok := plot == lot and lot.size.x >= 8 and lot.size.y >= 8
			# the ring of the lot's border: how much of it is free, side by side (a side with none is a lot cut by something)
			var ring := {"N": 0, "E": 0, "S": 0, "W": 0}
			var ring_n := {"N": 0, "E": 0, "S": 0, "W": 0}
			for x in range(lot.position.x, lot.end.x):
				ring_n["N"] += 1
				ring_n["S"] += 1
				ring["N"] += int(grid.open(x, lot.position.y))
				ring["S"] += int(grid.open(x, lot.end.y - 1))
			for y in range(lot.position.y, lot.end.y):
				ring_n["W"] += 1
				ring_n["E"] += 1
				ring["W"] += int(grid.open(lot.position.x, y))
				ring["E"] += int(grid.open(lot.end.x - 1, y))
			var hrect := Rect2i(h.rect)
			var made: Dictionary = Patrol.make_loop(plot, layout.inner, func(tx: int, ty: int) -> bool: return grid.open(tx, ty) and not hrect.has_point(Vector2i(tx, ty)), 3.0)
			var bad: Array = []
			if not rect_ok:
				bad.append("lot not a plain rectangle")
				sums.not_rect += 1
			else:
				sums.rect += 1
			var pts: Array = made.get("pts", [])
			var max_gap := 0.0
			var blocked := 0
			var outside := 0
			var per_side := {"N": 0, "E": 0, "S": 0, "W": 0}
			for i in pts.size():
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % pts.size()]
				max_gap = maxf(max_gap, a.distance_to(b))
				if not Rect2(lot).has_point(a):
					outside += 1
				per_side[String(made.side[i])] += 1
				# the straight link a to b: every tile along it open?
				var steps := int(ceil(a.distance_to(b) * 3.0))
				for s in range(1, steps):
					var q := a.lerp(b, float(s) / float(steps))
					if not grid.open(floori(q.x), floori(q.y)):
						blocked += 1
						break
			if pts.size() < 8:
				bad.append("only %d points" % pts.size())
			if outside > 0:
				bad.append("%d points outside the lot" % outside)
			if max_gap > 6.5:
				bad.append("a gap of %.1f tiles" % max_gap)
			for sd2 in per_side:
				if int(per_side[sd2]) < 2:
					bad.append("side %s has %d points" % [sd2, int(per_side[sd2])])
					sums.short_side += 1
			var problems: Array = BaseLayout.validate(layout, town)
			if not problems.is_empty():
				sums.problems += 1
				bad.append("layout problems: %s" % str(problems.slice(0, 2)))
			var towers := 0
			var fence_posts := 0
			var gates := 0
			for po in layout.posts:
				var sl := String(po.slot)
				if sl.begins_with("slot_tower"):
					towers += 1
				elif sl == String(layout.gate) and sl != "":
					gates += 1
				else:
					fence_posts += 1
			sums.towers += towers
			sums.gates += gates
			sums.fence_posts += fence_posts
			sums.blocked_links += blocked
			sums.max_gap = maxf(float(sums.max_gap), max_gap)
			sums.min_pts = mini(int(sums.min_pts), pts.size())
			sums.maxpts = maxi(int(sums.maxpts), pts.size())
			if not bad.is_empty():
				sums.bad_loop += 1
			var ringtxt := "ring free N %d/%d E %d/%d S %d/%d W %d/%d" % [ring.N, ring_n.N, ring.E, ring_n.E, ring.S, ring_n.S, ring.W, ring_n.W]
			_say("AUDIT seed=%d %s house %d lot %s front %s | %d pts, longest link %.1f, links cut by something %d | posts: %d towers %d fence %d gate | %s %s" % [
				int(sd), String(c.tier), hid, str(lot), String(h.front), pts.size(), max_gap, blocked, towers, fence_posts, gates, ringtxt, "OK" if bad.is_empty() else "!! " + "; ".join(bad)])
	_say("AUDIT SUMMARY candidates %d, plain rectangles %d, not %d, loops with a problem %d, links cut %d, longest link %.1f, points per loop %d to %d, layout problems %d, posts: towers %d fence %d gate %d" % [
		int(sums.cands), int(sums.rect), int(sums.not_rect), int(sums.bad_loop), int(sums.blocked_links), float(sums.max_gap), int(sums.min_pts), int(sums.maxpts), int(sums.problems), int(sums.towers), int(sums.fence_posts), int(sums.gates)])
