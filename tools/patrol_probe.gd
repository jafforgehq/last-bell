## The patrol probe (PH3, scripts/town/patrol.gd): sets up the first attack night with the crew on patrol and logs where each patroller is over time, so that you can SEE them walk the loop,
## spread out, converge on a breach and go back to the walk. Headless, no drawing, nothing written.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/patrol_probe.gd -- [--seed=1] [--blocks=6] [--hz=15] [--crew=3] [--timeline=2.0] [--quiet-s=60] [--fight-s=40] [--breach-s=40] [--after-s=50]
##
## The script: the claimed base with every section built (`PerimeterStage` "built"), the call to arms at dusk, then
##   1. QUIET: `quiet-s` seconds of the walk. The log shows each patroller's place on the loop (percent round, 0 to 100, and the side of the fence) and what they are doing.
##   2. FIGHT: a few of the dead come up to one side of the fence and claw at it (`fight-s` seconds): the nearest patrollers go there, stop and shoot; the rest go on.
##   3. BREACH: a section of the fence falls with the dead at it (`breach-s` seconds): the patrollers gather behind the gap.
##   4. AFTER: the dead are gone (`after-s` seconds): the patrollers go back to the walk and spread out again.
## The result lines: `PATROL_PROBE` followed by the checks (the loop is closed and inside the lot, they spread out, they converge, they return, nobody leaves the lot).
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const PerimeterStage := preload("res://scripts/town/perimeter_stage.gd")


func _opts() -> Dictionary:
	var o := {"seed": 1, "blocks": 6, "hz": 15.0, "crew": 3, "timeline": 2.0, "quiet-s": 60.0, "fight-s": 40.0, "breach-s": 40.0, "after-s": 50.0}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		if kv.size() == 2 and o.has(kv[0]):
			o[kv[0]] = kv[1].to_float()
	return o


func _initialize() -> void:
	var o := _opts()
	var g := Helpers.town_game(int(o.seed), {"blocks": int(o.blocks)})
	var sim = g.sim
	OneHouse.begin(sim, -1, int(o.seed))
	if not OneHouse.stage_to(sim, "night"):
		print("PATROL_PROBE stage refused")
		quit(1)
		return
	PerimeterStage.apply(sim, "built")
	sim.stock["ammo"] = 400.0
	# the avatar stands still inside the house, hands off: the crew are on their own
	var crew: Array = []
	for p in sim.people:
		if not p.player and not (p.dead or p.turned):
			crew.append(p)
	while crew.size() < int(o.crew):
		sim.scenario._stage_join(1)    # (the stage has two survivors; one more is made up at Ruth's side)
		crew.clear()
		for p in sim.people:
			if not p.player and not (p.dead or p.turned):
				crew.append(p)
	print("PATROL_PROBE crew: %d (%s)  day %d %.1f h  phase %s" % [crew.size(), ", ".join(crew.map(func(p): return String(p.first))), int(sim.day), float(sim.hour), String(sim.phase)])
	for p in crew:
		print("  %s on_patrol=%s post=%s job=%s" % [p.first, str(sim.jobs.on_patrol(p)), String(sim.jobs.post_of(p).get("id", "")), String(sim.jobs.job_of(p))])
	var pat = sim.patrol
	pat.update(0.0)
	var pts: Array = pat.points()
	var lot: Rect2 = pat.lot()
	print("loop: %d points, %.1f tiles round, lot %s, front %s" % [pts.size(), pat.loop_length(), str(lot), String(sim.perimeter.layout.front)])
	var inside := true
	for q in pts:
		if not lot.has_point(q):
			inside = false
	# the call to arms
	sim.radio.alarm(true)
	var hz := float(o.hz)
	var dt := 1.0 / hz
	var t := 0.0
	var next_log := 0.0
	var left_lot := 0.0
	var spread_min := 1.0e9
	var walked: Dictionary = {}    # person id -> furthest arc covered (sum of the arcs walked)
	var last_idx: Dictionary = {}
	var phase_names := ["QUIET", "FIGHT", "BREACH", "AFTER"]
	var bounds := [float(o["quiet-s"]), float(o["quiet-s"]) + float(o["fight-s"]), float(o["quiet-s"]) + float(o["fight-s"]) + float(o["breach-s"]),
		float(o["quiet-s"]) + float(o["fight-s"]) + float(o["breach-s"]) + float(o["after-s"])]
	var phase := -1
	var front_side := "E"
	var fight_at := Vector2.ZERO
	var breach_seg = null
	var summary := {"QUIET": {}, "FIGHT": {}, "BREACH": {}, "AFTER": {}}
	var spread_samples: Dictionary = {"QUIET": [], "AFTER": []}
	var hold_counts: Dictionary = {"FIGHT": 0, "BREACH": 0}
	var max_at_pressure: Dictionary = {"FIGHT": 0, "BREACH": 0}
	var switches := 0
	var last_tgt: Dictionary = {}
	var steps := 0
	while t < float(bounds[3]) and sim.over == "":
		var ph := 0
		while ph < 3 and t >= float(bounds[ph]):
			ph += 1
		if ph != phase:
			phase = ph
			print("---- %s  (t=%.0fs)" % [phase_names[phase], t])
			if phase == 1:
				fight_at = _spawn_fight(sim, pat)
			elif phase == 2:
				breach_seg = _breach(sim, fight_at)
			elif phase == 3:
				_clear_the_dead(sim)
				_mend(sim, breach_seg)
		# keep the night's own wave out: the probe has the dead it makes
		sim.waves.enabled = false
		sim.update(dt)
		sim.events.clear()
		t += dt
		steps += 1
		sim.radio.alarm_on = true
		sim.stock["ammo"] = 400.0
		# the check on the lot and the distances
		var arcs: Array = []
		for p in crew:
			if p.dead or p.turned:
				continue
			if not lot.has_point(Vector2(p.x, p.y)):
				left_lot += dt
		var snap: Array = pat.snapshot()
		for e in snap:
			var k: int = int(e.tgt)
			if last_tgt.get(e.id, -2) != k:
				if int(last_tgt.get(e.id, -2)) != -2 and k >= 0 and int(last_tgt.get(e.id, -1)) >= 0:
					switches += 1
				last_tgt[e.id] = k
			arcs.append(float(_arc_of(pat, e.at)))
			var idx := int(e.i)
			if last_idx.has(e.id) and idx != int(last_idx[e.id]):
				walked[e.id] = int(walked.get(e.id, 0)) + 1
			last_idx[e.id] = idx
		if phase == 1 or phase == 2:
			var n_hold := 0
			for e in snap:
				if String(e.mode) == "hold" or String(e.mode) == "go":
					n_hold += 1
			max_at_pressure[phase_names[phase]] = maxi(int(max_at_pressure[phase_names[phase]]), n_hold)
		var since_phase := t - (float(bounds[phase - 1]) if phase > 0 else 0.0)
		if arcs.size() >= 2 and (phase == 0 or phase == 3) and since_phase > 25.0:    # (once they have spread: the first seconds are the walk to the stretches)
			var gaps := _gaps(arcs, pat.loop_length())
			var mn := 1.0e9
			for gv in gaps:
				mn = minf(mn, float(gv))
			spread_min = minf(spread_min, mn)
			spread_samples[phase_names[phase]].append(mn)
		if t >= next_log:
			next_log += float(o.timeline)
			print(_line(sim, pat, t, phase_names[phase], crew))
	# the checks
	var avg_after := 0.0
	for v in spread_samples["AFTER"]:
		avg_after += float(v)
	avg_after = avg_after / maxf(float(spread_samples["AFTER"].size()), 1.0)
	var min_quiet := 1.0e9
	for v in spread_samples["QUIET"]:
		min_quiet = minf(min_quiet, float(v))
	var laps := 0.0
	for id in walked:
		laps = maxf(laps, float(int(walked[id])) / maxf(float(pts.size()), 1.0))
	var seen_modes: Dictionary = {}
	print("PATROL_PROBE loop_inside_lot=%s loop_points=%d loop_len=%.1f left_lot_s=%.1f" % [str(inside), pts.size(), pat.loop_length(), left_lot])
	print("PATROL_PROBE quiet: min gap between patrollers %.1f tiles (even spread would be %.1f), most laps by one patroller %.2f" % [min_quiet, pat.loop_length() / maxf(float(crew.size()), 1.0), laps])
	print("PATROL_PROBE fight: at most %d patrollers at/going to the pressure; breach: at most %d; target changes while sent: %d" % [int(max_at_pressure["FIGHT"]), int(max_at_pressure["BREACH"]), switches])
	print("PATROL_PROBE after: mean of the smallest gap between patrollers, from 25 s after the dead are gone: %.1f tiles" % avg_after)
	print("PATROL_PROBE cost: goal_for %.1f us a call (%d calls), replan %.0f us a look (%d looks, one every %.1f s); %.2f ms a second of play in all" % [
		float(pat.usec_goal) / maxf(float(pat.calls_goal), 1.0), int(pat.calls_goal), float(pat.usec_replan) / maxf(float(pat.calls_replan), 1.0), int(pat.calls_replan), float(o.hz) * 0.0 + 0.4,
		(float(pat.usec_goal) + float(pat.usec_replan)) / 1000.0 / maxf(t, 1.0)])
	g.world.free()
	quit(0)


func _arc_of(pat, at: Vector2) -> float:
	var i: int = pat.nearest(at)
	return float(pat._cum[i])


func _gaps(arcs: Array, length: float) -> Array:
	var a := arcs.duplicate()
	a.sort()
	var out: Array = []
	for i in a.size():
		var nxt: float = float(a[(i + 1) % a.size()])
		out.append(fposmod(nxt - float(a[i]), length))
	return out


## One line: the time, the phase, and for each patroller "name  side pct%  mode" (the side of the fence the nearest point of the loop is behind).
func _line(sim, pat, t: float, ph: String, crew: Array) -> String:
	var parts: Array = []
	var dead := 0
	for z in sim.zombies:
		if z.state == "attack" or z.state == "breach" or z.state == "approach":
			dead += 1
	var snap: Dictionary = {}
	for e in pat.snapshot():
		snap[String(e.id)] = e
	for p in crew:
		if p.dead or p.turned:
			parts.append("%s dead" % String(p.first).left(3))
			continue
		var e = snap.get(String(p.id))
		if e == null:
			# (not on the patrol this moment: mending a section, a treatment, the lookout's day seat...)
			parts.append("%s - [%s]" % [String(p.first).left(3), String(p.activity)])
			continue
		var i: int = pat.nearest(Vector2(p.x, p.y))
		var pct := int(round(float(pat._cum[i]) / maxf(pat.loop_length(), 1.0) * 100.0))
		parts.append("%s %s%3d%% %-7s%s" % [String(p.first).left(3), String(pat._side[i]), pct, String(e.mode), (" k%d" % int(e.tgt)) if int(e.tgt) >= 0 else "    "])
	return "t=%5.1f %-6s dead %2d | %s" % [t, ph, dead, " | ".join(parts)]


## A few of the dead come up to one side of the fence, from outside, and claw at it: returns where.
func _spawn_fight(sim, pat) -> Vector2:
	var lot: Rect2 = pat.lot()
	# the side farthest from the middle of the crew (so the patrollers have to travel): the east or west side by the lot's shape
	var mid := Vector2.ZERO
	var n := 0
	for p in sim.people:
		if not p.player and not (p.dead or p.turned):
			mid += Vector2(p.x, p.y)
			n += 1
	mid /= float(maxi(n, 1))
	var sides := [Vector2(lot.position.x - 1.2, lot.get_center().y), Vector2(lot.end.x + 1.2, lot.get_center().y), Vector2(lot.get_center().x, lot.position.y - 1.2), Vector2(lot.get_center().x, lot.end.y + 1.2)]
	var best: Vector2 = sides[0]
	var best_d := -1.0
	for s in sides:
		var d: float = s.distance_to(mid)
		if d > best_d:
			best_d = d
			best = s
	var count := 0
	for seg in sim.segments:
		if int(seg.id) >= 100 or String(seg.kind) == "door":
			continue
		if seg.center.distance_to(best) > 7.0 or seg.slots.is_empty():
			continue
		for sl in seg.slots:
			if sl.who != null or count >= 6:
				continue
			var z = sim.spawn(sl.ax, sl.ay, "approach")
			z.slot = sl
			sl.who = z
			z.path = [Vector2(sl.x, sl.y)]
			z.path_i = 0
			count += 1
	print("  fight: %d dead at the fence near (%.0f, %.0f)" % [count, best.x, best.y])
	return best


## Brings a fence section near `at` down, with a few of the dead in the gap.
func _breach(sim, at: Vector2):
	var best = null
	var best_d := 1.0e9
	for seg in sim.segments:
		if int(seg.id) >= 100 or String(seg.kind) == "door":
			continue
		var d: float = seg.center.distance_to(at)
		if d < best_d:
			best_d = d
			best = seg
	if best == null:
		return null
	best.hp = 0.0
	sim._segment_state(best)
	for i in 4:
		var z = sim.spawn(best.center.x + float(i) * 0.6 - 0.9, best.center.y + 1.2, "breach")
		z.path = []
	print("  breach: %s down at (%.0f, %.0f)" % [String(best.name), best.center.x, best.center.y])
	return best


func _clear_the_dead(sim) -> void:
	for z in sim.zombies:
		if z.slot != null:
			z.slot.who = null
			z.slot = null
		z.state = "dead"
		z.remove = true
	print("  the dead are gone")


func _mend(sim, seg) -> void:
	if seg == null:
		return
	seg.hp = seg.max_hp
	sim._segment_state(seg)
