## What the dead cost the rules (DEAD1, 2026-10-10): the microseconds one rules step takes with many of the dead awake, headless (the sim side of the single-threaded web build's question; the draw
## side is tools/town_bench.gd `--what=game --scenes=night --wave=N`). From the repo root:
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/dead_probe.gd -- --what=night --seed=1 --first=7 [--cap=70] [--steps=9000] [--web]
##   $G --headless --path . --script res://tools/dead_probe.gd -- --what=walk --seed=1 [--steps=6000]
##
## night: the first attack night of the town (`OneHouse.stage_to "night"`: a claimed house, a crew of three, the dusk at hand) with the night made as big as `--first` says (`night.first`; 7 gives
## about 75 of the dead), all in one surge (`--surge=0` keeps the data's three), the avatar kept alive and still, the crew at the fence; every step of the rules is timed (`sim.update`) and filed
## under how many of the dead were awake at that moment. walk: the claimed house by day, the avatar walks from street to street (`--routes=N` legs of a route that is the same for the same seed
## and town) among the street's dead, which wake and sleep as she goes; the same numbers. `--web`: the platform's caps of the web build (`TownPerf`: 40 awake of the street, 12 path searches a step).
## Whatever the machine does around it makes the numbers move: run it twice and compare with a run of the same tool on the other tree, not with a number in a document.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const TownPerf := preload("res://scripts/town/town_perf.gd")
const PerimeterStage := preload("res://scripts/town/perimeter_stage.gd")

var _a := {}
## The bins of the awake dead (lower edge) a step is filed under.
const BINS := [0, 10, 25, 40, 55, 70, 90]


func _initialize() -> void:
	_main.call_deferred()


func _arg(k: String, d: String) -> String:
	return String(_a.get(k, d))


func _main() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := String(arg).trim_prefix("--").split("=", true, 1)
		_a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed_value := int(_arg("seed", "1"))
	var what := _arg("what", "night")
	var t_make := Time.get_ticks_usec()
	var g := Helpers.town_game(seed_value, {"blocks": 6})
	var sim = g.sim
	var world = g.world
	OneHouse.begin(sim, -1, seed_value)
	var data: Dictionary = sim.scenario.d()
	if _a.has("first"):
		data["night"]["first"] = float(_arg("first", "1.85"))
	if _a.has("cap"):
		data["big_night"]["cap"] = int(_arg("cap", "70"))
		data["night"]["cap_dusk"] = int(_arg("cap", "70"))
		data["night"]["cap_night"] = int(_arg("cap", "70"))
	if what == "night" and _arg("surge", "1") == "1":
		data["night"]["surges"] = [{"at": 0.3, "share": 1.0}]
	if _a.has("web"):
		sim.field.active_cap = TownPerf.ACTIVE_CAP_WEB
		sim.path_budget = TownPerf.PATH_BUDGET_WEB
	if _a.has("active_cap"):
		sim.field.active_cap = int(_arg("active_cap", "60"))
	print("== dead probe: %s, seed %d, %d dead in the town (%d ms to make), field cap %d, path budget %d" % [what, seed_value, sim.field.n, (Time.get_ticks_usec() - t_make) / 1000, sim.field.active_cap, sim.path_budget])
	if what == "night":
		_night(sim, int(_arg("steps", "9000")))
	else:
		_walk(sim, world, int(_arg("steps", "6000")), int(_arg("routes", "14")))
	world.free()
	quit(0)


func _awake(sim) -> int:
	var n := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			n += 1
	return n


func _bin(n: int) -> int:
	var b := 0
	for i in BINS.size():
		if n >= int(BINS[i]):
			b = i
	return b


class Rec:
	extends RefCounted
	var us := PackedFloat64Array()
	var awake := 0
	var chase := 0
	var sep := 0
	var finds := 0
	var wake := 0
	var sleep := 0


func _report(label: String, recs: Array, all_us: PackedFloat64Array, peak: int, finds_max: int) -> void:
	print("-- %s: %d steps, the most awake at once %d, path searches in one step at most %d" % [label, all_us.size(), peak, finds_max])
	print("   awake      steps   mean ms   p50     p95     p99     max   | sep    chase  field(wake+sleep) us per step")
	for i in recs.size():
		var r: Rec = recs[i]
		if r.us.size() == 0:
			continue
		var s := r.us.duplicate()
		s.sort()
		var sum := 0.0
		for v in s:
			sum += v
		var n := float(s.size())
		print("   %3d..%-4s %6d   %6.3f  %6.3f  %6.3f  %6.3f  %6.3f   | %5.0f  %5.0f  %5.0f" % [BINS[i], str(int(BINS[i + 1]) - 1) if i + 1 < BINS.size() else "", s.size(), sum / n / 1000.0, s[int(n * 0.5)] / 1000.0, s[int(minf(n - 1.0, n * 0.95))] / 1000.0, s[int(minf(n - 1.0, n * 0.99))] / 1000.0, s[s.size() - 1] / 1000.0, float(r.sep) / n, float(r.chase) / n, float(r.wake + r.sleep) / n])
	var a := all_us.duplicate()
	a.sort()
	var tot := 0.0
	for v in a:
		tot += v
	if a.size() > 0:
		print("   all steps   %6d   %6.3f  %6.3f  %6.3f  %6.3f  %6.3f" % [a.size(), tot / float(a.size()) / 1000.0, a[a.size() / 2] / 1000.0, a[int(minf(float(a.size() - 1), float(a.size()) * 0.95))] / 1000.0, a[int(minf(float(a.size() - 1), float(a.size()) * 0.99))] / 1000.0, a[a.size() - 1] / 1000.0])


func _new_recs() -> Array:
	var recs: Array = []
	for i in BINS.size():
		recs.append(Rec.new())
	return recs


## Files one step: its time and the part the field, the crowd pass and the chase took.
func _file(recs: Array, sim, us: float, sep0: int, chase0: int, wake0: int, sleep0: int) -> void:
	var r: Rec = recs[_bin(_awake(sim))]
	r.us.append(us)
	r.sep += sim.sep_usec - sep0
	r.chase += sim.chase_usec - chase0
	r.wake += sim.field.wake_usec - wake0
	r.sleep += sim.field.sleep_usec - sleep0


func _night(sim, max_steps: int) -> void:
	OneHouse.stage_to(sim, "night")
	if _arg("slots", "built") != "none":
		PerimeterStage.apply(sim, _arg("slots", "built"))    # (the base as a bot has it by the first night: every section of the fence, the gate and the towers up)
	var me = sim.avatar.player()
	var dt := 1.0 / 30.0
	var recs := _new_recs()
	var all_us := PackedFloat64Array()
	var peak := 0
	var finds_max := 0
	var wave_peak := 0
	var steps := 0
	var started_night := false
	var micro_done := false
	var last_alive := 0
	var line_at := 0
	while steps < max_steps and sim.over == "":
		me.hp = 100.0
		me.downed = false
		var sep0: int = sim.sep_usec
		var chase0: int = sim.chase_usec
		var wake0: int = sim.field.wake_usec
		var sleep0: int = sim.field.sleep_usec
		var t0 := Time.get_ticks_usec()
		sim.update(dt)
		var us := float(Time.get_ticks_usec() - t0)
		sim.events.clear()
		steps += 1
		if sim.phase == "night" or sim.phase == "dusk":
			started_night = true
		var alive := _awake(sim)
		var wave := int(sim.alive_for_cap())
		peak = maxi(peak, alive)
		wave_peak = maxi(wave_peak, wave)
		finds_max = maxi(finds_max, int(sim.finds_last))
		if started_night:
			_file(recs, sim, us, sep0, chase0, wake0, sleep0)
			all_us.append(us)
		last_alive = alive
		if alive >= 65 and not micro_done and _arg("micro", "") != "":
			micro_done = true
			var tb := Time.get_ticks_usec()
			for i in 300:
				sim._separate()
			var t_sep := float(Time.get_ticks_usec() - tb) / 300.0
			tb = Time.get_ticks_usec()
			for i in 300:
				sim.dead_inside()
			var t_in := float(Time.get_ticks_usec() - tb) / 300.0
			tb = Time.get_ticks_usec()
			for i in 300:
				sim._notice()
			var t_no := float(Time.get_ticks_usec() - tb) / 300.0
			print("   MICRO at %d awake (%d zombies in the list): _separate %.0f us, dead_inside %.0f us, _notice %.0f us" % [alive, sim.zombies.size(), t_sep, t_in, t_no])
		if started_night and us > 8000.0:
			print("   a slow step: %.1f ms at t=%.1f s, %d awake, %d path searches" % [us / 1000.0, float(steps) * dt, alive, int(sim.finds_last)])
		if steps - line_at >= 900:
			line_at = steps
			print("   t=%5.0f s  day %d %05.2f %s  awake %d (the night's %d)  step %.2f ms" % [float(steps) * dt, sim.day, sim.hour, sim.phase, alive, wave, us / 1000.0])
		if started_night and sim.phase == "day" and steps > 300 and wave == 0:
			break
	var plan: Dictionary = sim.waves.plan_for(sim.scenario._first_day) if sim.waves != null else {}
	print("   the night's plan: %d dead (%s), the most of them alive at once %d, the most awake of all %d, the last step had %d awake" % [int(plan.get("queue", []).size()), str(plan.get("counts", {})), wave_peak, peak, last_alive])
	_report("night", recs, all_us, peak, finds_max)


func _walk(sim, world, max_steps: int, routes: int) -> void:
	OneHouse.stage_to(sim, "claimed")
	sim.minutes = 10.0 * 60.0
	var me = sim.avatar.player()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var dt := 1.0 / 30.0
	var recs := _new_recs()
	var all_us := PackedFloat64Array()
	var peak := 0
	var finds_max := 0
	var steps := 0
	var path: Array = []
	var pi := 0
	var legs := 0
	var awake_sum := 0.0
	var woke0: int = sim.field.woke_total
	while steps < max_steps and sim.over == "" and legs <= routes:
		me.hp = 100.0
		me.downed = false
		sim.minutes = maxf(sim.minutes, 0.0)
		if sim.phase != "day":
			sim.minutes = 10.0 * 60.0    # (the walk is by day)
		if pi >= path.size():
			var tgt := Vector2.ZERO
			for k in 400:
				tgt = Vector2(rng.randf_range(10.0, 182.0), rng.randf_range(10.0, 182.0))
				if not world.is_solid(world.solid_p, tgt.x, tgt.y):
					break
			path = sim.path_p.find(world.solid_p, me.x, me.y, tgt.x, tgt.y)
			pi = 0
			legs += 1
			if path.is_empty():
				continue
		var wp: Vector2 = path[pi]
		var to := wp - Vector2(me.x, me.y)
		var stp := 4.0 * dt
		if to.length() <= stp:
			me.x = wp.x
			me.y = wp.y
			pi += 1
		else:
			var d := to.normalized() * stp
			me.x += d.x
			me.y += d.y
		var sep0: int = sim.sep_usec
		var chase0: int = sim.chase_usec
		var wake0: int = sim.field.wake_usec
		var sleep0: int = sim.field.sleep_usec
		var t0 := Time.get_ticks_usec()
		sim.update(dt)
		var us := float(Time.get_ticks_usec() - t0)
		sim.events.clear()
		steps += 1
		var alive := _awake(sim)
		awake_sum += float(alive)
		peak = maxi(peak, alive)
		finds_max = maxi(finds_max, int(sim.finds_last))
		_file(recs, sim, us, sep0, chase0, wake0, sleep0)
		all_us.append(us)
	print("   walked %d legs in %d steps (%.0f game seconds), woke %d of the street's dead, %.1f awake on average, %d records in the field" % [legs, steps, float(steps) * dt, sim.field.woke_total - woke0, awake_sum / maxf(float(steps), 1.0), sim.field.n])
	_report("walk by day", recs, all_us, peak, finds_max)
