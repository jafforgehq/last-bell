## Headless measurements of the town's rules (the sim side of the question). From the repo root:
##
##   Godot --headless --path . --script res://tools/town_bench.gd -- [--what=build,paths,fight,churn,save] [--n=0,60,100,160,240] [--steps=600]
##
## `build`: the generator, World.build, the sim and its grids; `paths`: A* and sight costs; `fight`: N of the dead after the avatar, per step, for the
## base's way (hunt, square crowd pass) and the new one (chase, grid crowd pass); `churn`: the avatar crosses the town with the dormant field live;
## `save`: sizes of a save.
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const TownRun := preload("res://scripts/town/town_run.gd")
const TownBoot := preload("res://scripts/town/town_boot.gd")
const World := preload("res://scripts/world.gd")
const TownWorld := preload("res://scripts/town/town_world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

var _args := {}
var _town: Dictionary
var _world


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return default


func _initialize() -> void:
	var what := _arg("what", "build,paths,flow,fight,churn,save").split(",")
	var t0 := Time.get_ticks_usec()
	var mem0 := OS.get_static_memory_usage()
	_town = TownGen.make(int(_arg("seed", "1")))
	var mem1 := OS.get_static_memory_usage()
	print("== town: %s" % JSON.stringify(_town.stats))
	print("memory: the town's data (map arrays, objects, records, tile indexes) %.1f MB" % [float(mem1 - mem0) / 1048576.0])
	if "build" in what:
		_bench_build()
	else:
		_make_world()
	if "paths" in what:
		_bench_paths()
	if "flow" in what:
		_bench_flow()
	if "fight" in what:
		_bench_fight()
	if "churn" in what:
		_bench_churn()
	if "save" in what:
		_bench_save()
	quit()


func _make_world() -> void:
	_world = World.new()
	root.add_child(_world)
	_world.build(_town.data)


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _bench_build() -> void:
	var t := Time.get_ticks_usec()
	var m0 := OS.get_static_memory_usage()
	_world = World.new()
	root.add_child(_world)
	_world.build(_town.data)
	var ms_world := float(Time.get_ticks_usec() - t) / 1000.0
	print("memory: the town's World nodes (ground meshes, sprites, paint) %.1f MB" % [float(OS.get_static_memory_usage() - m0) / 1048576.0])
	print("World.build as it is (ground meshes, ground details, %d object sprites): %.1f ms, %d nodes" % [_town.data.objects.size(), ms_world, _count_nodes(_world)])
	var tw = TownWorld.new()
	root.add_child(tw)
	t = Time.get_ticks_usec()
	tw.build(_town.data)
	print("TownWorld.build (stepped version run in one go; chunked paint not drawn yet): %.1f ms, %d nodes, phases %s" % [float(Time.get_ticks_usec() - t) / 1000.0, _count_nodes(tw), JSON.stringify(tw.build_ms)])
	tw.queue_free()
	t = Time.get_ticks_usec()
	t = Time.get_ticks_usec()
	m0 = OS.get_static_memory_usage()
	var sim = (load("res://scripts/town/town_sim.gd") as GDScript).new(TownBoot.from_town(_town), _world, FxNull.new())
	var ms_sim := float(Time.get_ticks_usec() - t) / 1000.0
	print("memory: TownSim (two AStarGrid2D %dx%d, the colony's modules) %.1f MB" % [sim.W, sim.H, float(OS.get_static_memory_usage() - m0) / 1048576.0])
	print("TownSim.new (all the colony modules + path_z + path_p AStarGrid2D %dx%d): %.1f ms" % [sim.W, sim.H, ms_sim])
	t = Time.get_ticks_usec()
	var ps = (load("res://scripts/sim/pathfinder.gd") as GDScript).new(sim.W, sim.H, _world.solid_z)
	print("one Pathfinder.new (grid.update + %d solid cells): %.1f ms" % [sim.W * sim.H, float(Time.get_ticks_usec() - t) / 1000.0])
	t = Time.get_ticks_usec()
	sim._regions_dirty = true
	var r: int = sim.region_at(1.5, 1.5)
	print("region flood (_compute_regions) on the town: %.1f ms (the base redoes it after every door, wall or build; hunt asks it twice a step)" % [float(Time.get_ticks_usec() - t) / 1000.0])
	ps = ps
	r = r
	var mem_grid := 0
	print("arrays: terrain/solidZ/solidP in the map dictionary are Array[int] of %d each (the data) + 3 packed copies in World" % [sim.W * sim.H])
	print("static memory now: %.1f MB (Performance.MEMORY_STATIC)" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	mem_grid = mem_grid


## A flow field (a breadth first distance field from one target over the walking grid, 8 ways, no corner cutting): what it would cost to recompute, whole grid and
## limited to a radius, against the A* each chaser asks. Memory: one int16 a tile.
func _bench_flow() -> void:
	if _world == null:
		_make_world()
	var W: int = _world.W
	var H: int = _world.H
	var solid: PackedByteArray = _world.solid_z
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for radius in [1000, 45, 28]:
		var total_us := 0
		var reached_sum := 0
		var runs := 12
		for r in runs:
			var sx := 0
			var sy := 0
			while true:
				sx = rng.randi_range(8, W - 8)
				sy = rng.randi_range(8, H - 8)
				if solid[sy * W + sx] == 0:
					break
			var t := Time.get_ticks_usec()
			var dist := PackedInt32Array()
			dist.resize(W * H)
			dist.fill(-1)
			var q := PackedInt32Array()
			q.resize(W * H)
			var head := 0
			var tail := 0
			q[tail] = sy * W + sx
			tail += 1
			dist[sy * W + sx] = 0
			while head < tail:
				var i := q[head]
				head += 1
				var d := dist[i]
				if d >= radius:
					continue
				var x := i % W
				@warning_ignore("integer_division")
				var y := i / W
				for k in 4:
					var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
					var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					if dist[j] != -1 or solid[j] != 0:
						continue
					dist[j] = d + 1
					q[tail] = j
					tail += 1
			total_us += Time.get_ticks_usec() - t
			reached_sum += tail
		print("flow field (4-way BFS, int32 a tile = %.0f KB) radius %4d tiles: %.2f ms per recompute, %d tiles reached on average" % [float(W * H * 4) / 1024.0, radius, float(total_us) / runs / 1000.0, reached_sum / runs])


func _walkable_pairs(count: int, dist_lo: float, dist_hi: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var W: int = _world.W
	var tries := 0
	while out.size() < count and tries < count * 400:
		tries += 1
		var a := Vector2(rng.randf_range(4.0, W - 4.0), rng.randf_range(4.0, W - 4.0))
		var ang := rng.randf() * TAU
		var b := a + Vector2.from_angle(ang) * rng.randf_range(dist_lo, dist_hi)
		if b.x < 4.0 or b.y < 4.0 or b.x > W - 4.0 or b.y > W - 4.0:
			continue
		if _world.is_solid(_world.solid_z, a.x, a.y) or _world.is_solid(_world.solid_z, b.x, b.y):
			continue
		out.append([a, b])
	return out


func _bench_paths() -> void:
	if _world == null:
		_make_world()
	var sim = (load("res://scripts/town/town_sim.gd") as GDScript).new(TownBoot.from_town(_town), _world, FxNull.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for band in [[6.0, 12.0], [12.0, 25.0], [25.0, 45.0], [45.0, 90.0]]:
		var pairs := _walkable_pairs(150, band[0], band[1], rng)
		var t := Time.get_ticks_usec()
		var found := 0
		var pts := 0
		sim.path_z.find_calls = 0
		sim.path_z.find_usec = 0
		for p in pairs:
			var path: Array = sim.path_z.find(_world.solid_z, p[0].x, p[0].y, p[1].x, p[1].y)
			if not path.is_empty():
				found += 1
				pts += path.size()
		var us := float(sim.path_z.find_usec) / maxf(1.0, float(sim.path_z.find_calls))
		print("A* find (smoothed) %2d-%2d tiles apart: %.0f us each over %d (%d found, %.1f waypoints on average)" % [band[0], band[1], us, pairs.size(), found, float(pts) / maxf(1.0, float(found))])
	# the sight test
	for dist in [4.0, 8.0, 14.0, 30.0]:
		var pairs := _walkable_pairs(300, dist, dist, rng)
		var t2 := Time.get_ticks_usec()
		var clear := 0
		for p in pairs:
			if sim.path_z.sight(_world.solid_z, p[0], p[1], 0.3):
				clear += 1
		print("sight line %.0f tiles: %.1f us each (%d of %d clear)" % [dist, float(Time.get_ticks_usec() - t2) / float(maxi(1, pairs.size())), clear, pairs.size()])


## A route round the blocks of the middle of the town that the avatar walks in a fight (streets only): waypoints in tiles.
func _route() -> Array:
	var c := 96.0
	return [Vector2(c - 2.0, c - 2.0), Vector2(c + 30.0, c - 2.0), Vector2(c + 30.0, c + 30.0), Vector2(c - 2.0, c + 30.0), Vector2(c - 2.0, c - 2.0)]


func _street_start() -> Vector2:
	# a crossing near the middle: roads at x, y = 28 + 32k .. +4
	return Vector2(94.0, 94.0)


func _fight(n: int, chase: bool, grid: bool, steps: int, seed_value: int) -> Dictionary:
	var town_nodead := _town.duplicate(false)
	town_nodead["dead"] = []
	town_nodead["start"] = {"house": 0, "pos": _street_start()}
	var run = TownRun.new(town_nodead, _world, FxNull.new(), 1000, chase, grid)
	run.invulnerable = true
	var sim = run.sim
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var me: Vector2 = _street_start()
	var tries := 0
	var made := 0
	while made < n and tries < n * 100:
		tries += 1
		var p := me + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 26.0)
		if _world.is_solid(_world.solid_z, p.x, p.y):
			continue
		var z = sim.spawn(p.x, p.y, "wander", "walker" if rng.randf() < 0.85 else "runner")
		sim.start_chase(z, run.avatar_p)
		z.repath = rng.randf() * 1.0
		made += 1
	sim.events.clear()
	var route := _route()
	var leg := 0
	var times := PackedFloat64Array()
	var dt := 1.0 / 30.0
	var warm := 60
	sim.path_z.find_calls = 0
	sim.path_z.find_usec = 0
	var bites := 0
	for s in steps + warm:
		var pl = run.avatar_p
		var tgt: Vector2 = route[(leg + 1) % route.size()]
		var to := tgt - Vector2(pl.x, pl.y)
		if to.length() < 0.6:
			leg = (leg + 1) % route.size()
		sim.avatar.set_input(to, tgt, false)
		if s == warm:
			run.prof_reset()
			sim.sep_usec = 0
			sim.chase_usec = 0
			sim.chase_n = 0
			sim.path_z.find_calls = 0
			sim.path_z.find_usec = 0
		var t := Time.get_ticks_usec()
		run.update(dt)
		if s >= warm:
			times.append(float(Time.get_ticks_usec() - t))
	times.sort()
	var total := 0.0
	for v in times:
		total += v
	var steps_n := float(times.size())
	var res := {
		"n": n, "mean_ms": total / steps_n / 1000.0, "p50_ms": times[times.size() / 2] / 1000.0, "p95_ms": times[int(steps_n * 0.95)] / 1000.0, "max_ms": times[times.size() - 1] / 1000.0,
		"sep_ms": float(sim.sep_usec) / steps_n / 1000.0, "chase_ms": float(sim.chase_usec) / steps_n / 1000.0,
		"astar_calls_s": float(sim.path_z.find_calls) / (steps_n / 30.0), "astar_ms_step": float(sim.path_z.find_usec) / steps_n / 1000.0,
		"alive": sim.zombies.size(), "chasing": 0,
	}
	var ch := 0
	for z in sim.zombies:
		if z.state == "chase" or z.state == "hunt":
			ch += 1
	res.chasing = ch
	return res


func _bench_fight() -> void:
	if _world == null:
		_make_world()
	var ns := _arg("n", "0,60,100,160,240").split(",")
	var steps := int(_arg("steps", "600"))
	print("== fight: the avatar walks the streets, N of the dead after them (per rules step of 1/30 s; a 60 fps frame has 16.7 ms and the rules take 1 step in 2 frames)")
	for cfg in [["base (hunt, square crowd pass)", false, false], ["grid crowd pass only (hunt)", false, true], ["new (chase, grid crowd pass)", true, true]]:
		for n in ns:
			var r := _fight(int(n), cfg[1], cfg[2], steps, 5)
			print("%-34s N=%3d  step mean %6.2f  p50 %6.2f  p95 %6.2f  max %6.2f ms | crowd pass %6.2f  chase %5.2f | A* %5.1f/s %5.2f ms/step | chasing %d of %d" % [cfg[0], r.n, r.mean_ms, r.p50_ms, r.p95_ms, r.max_ms, r.sep_ms, r.chase_ms, r.astar_calls_s, r.astar_ms_step, r.chasing, r.alive])


func _bench_churn() -> void:
	if _world == null:
		_make_world()
	for cap in [100, 60]:
		var run = TownRun.new(_town, _world, FxNull.new(), cap, true, true)
		run.invulnerable = true
		var sim = run.sim
		sim.events.clear()
		# the avatar walks the town along the roads (a path of the people's grid for each leg), a shot's noise every three seconds
		var route := [Vector2(94.5, 91.5), Vector2(158.5, 91.5), Vector2(158.5, 155.5), Vector2(30.5, 155.5), Vector2(30.5, 27.5), Vector2(94.5, 27.5), Vector2(94.5, 91.5)]
		run.avatar_p.x = 94.5
		run.avatar_p.y = 91.5
		var leg := 0
		var path: Array = []
		var path_i := 0
		var dt := 1.0 / 30.0
		var steps := 30 * 200
		var worst := 0.0
		var sum := 0.0
		var peak_active := 0
		var active_sum := 0
		var field = run.field
		var times := PackedFloat64Array()
		var worst_step := -1
		for s in steps:
			var pl = run.avatar_p
			if path_i >= path.size():
				leg = (leg + 1) % (route.size() - 1)
				var tgt: Vector2 = route[leg + 1]
				path = sim.path_p.find(_world.solid_p, pl.x, pl.y, tgt.x, tgt.y)
				path_i = 0
				if path.is_empty():
					path = [tgt]
			var wp: Vector2 = path[path_i]
			var to: Vector2 = wp - Vector2(pl.x, pl.y)
			if to.length() < 0.5:
				path_i += 1
			sim.avatar.set_input(to, wp, false)
			if s % 90 == 45:
				sim._shot_noise(pl)
			var t := Time.get_ticks_usec()
			run.update(dt)
			var us := float(Time.get_ticks_usec() - t)
			times.append(us)
			sum += us
			if us > worst:
				worst = us
				worst_step = s
			active_sum += field.active_of.size()
			peak_active = maxi(peak_active, field.active_of.size())
		times.sort()
		var shot_n := 0
		print("churn cap %3d: %d steps (%.0f s, %d noises): step mean %.2f p50 %.2f p95 %.2f p99 %.2f max %.2f ms | active mean %.1f peak %d | woke %d slept %d killed %d | dormant %d | wake pass %.0f us/call, sleep pass %.0f us/call | A* %d calls" % [cap, steps, float(steps) / 30.0, steps / 90, sum / steps / 1000.0, times[steps / 2] / 1000.0, times[int(steps * 0.95)] / 1000.0, times[int(steps * 0.99)] / 1000.0, worst / 1000.0, float(active_sum) / steps, peak_active, field.woke_total, field.slept_total, field.killed_total, field.counts().dormant, float(field.wake_usec) / maxf(1.0, float(steps) / 7.5), float(field.sleep_usec) / maxf(1.0, float(steps) / 7.5), sim.path_z.find_calls])
		shot_n = shot_n


func _bench_save() -> void:
	if _world == null:
		_make_world()
	var run = TownRun.new(_town, _world, FxNull.new(), 100, true, true)
	var d: Dictionary = run.field.save()
	var js := JSON.stringify(d)
	print("dormant field save: %d records -> %d bytes of JSON (%.1f bytes each)" % [run.field.n, js.length(), float(js.length()) / maxf(1.0, float(run.field.n))])
	# a real zombie, the way the colony's save writes it
	var z = run.sim.spawn(100.0, 100.0, "wander", "walker")
	var zjs := JSON.stringify(SaveGame._zombie_out(z))
	print("one real Zombie in the colony's save: %d bytes of JSON -> 800 of them: %.1f KB, 100 of them: %.1f KB" % [zjs.length(), float(zjs.length()) * 800.0 / 1024.0, float(zjs.length()) * 100.0 / 1024.0])
	print("sample record: %s" % zjs.substr(0, 300))
