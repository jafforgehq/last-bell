## Headless measurements of the town's rules (the sim side of the question). From the repo root:
##
##   Godot --headless --path . --script res://tools/town_bench.gd -- [--what=build,paths,fight,churn,save] [--n=0,60,100,160,240] [--steps=600]
##
## `build`: the generator, World.build, the sim and its grids; `paths`: A* and sight costs; `fight`: N of the dead after the avatar, per step, for the
## base's way (hunt, square crowd pass) and the new one (chase, grid crowd pass); `churn`: the avatar crosses the town with the dormant field live;
## `save`: sizes of a save; `game`: the REAL game (scenes/main.tscn on the town, the HUD, the roofs, the pawns) driven through a list of situations, frame by frame:
##
##   Godot --path . --script res://tools/town_bench.gd -- --what=game [--scenes=house,street,...] [--frames=300] [--warm=90] [--size=1280x800] [--seed=1]
##   (windowed: draw calls, render time and nodes are real, vsync is off; with --headless only the script side is measured)
##   scenes: house, street, walk, dead60, dead100, night, roofs, mapzoom, save (the last prints the size and the time of a save and of a load)
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const TownRun := preload("res://scripts/town/town_run.gd")
const TownBoot := preload("res://scripts/town/town_boot.gd")
const World := preload("res://scripts/world.gd")
const TownWorld := preload("res://scripts/town/town_world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")

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
	if "game" in what:
		_game_start()
		return
	if "load" in what:
		_bench_load()
		quit()
		return
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


## The pieces of a town run's start, one by one (the order of Main._ready): where the loading card's milliseconds go.
func _bench_load() -> void:
	var t := Time.get_ticks_usec()
	var g := TownGen.new()
	g.begin(int(_arg("seed", "1")), {})
	var frames := 0
	var worst := 0.0
	while true:
		var t1 := Time.get_ticks_usec()
		var done: bool = g.step(float(_arg("budget", "12")))
		worst = maxf(worst, float(Time.get_ticks_usec() - t1) / 1000.0)
		frames += 1
		if done:
			break
	var town: Dictionary = g.result()
	print("[load] generator phases (ms): %s" % JSON.stringify(town.stats.get("ms", town.stats)))
	print("[load] TownGen stepped (%s ms budget): %.1f ms in %d steps (the worst step %.1f ms)" % [_arg("budget", "12"), float(Time.get_ticks_usec() - t) / 1000.0, frames, worst])
	t = Time.get_ticks_usec()
	var d: Dictionary = TownBoot.from_town(town)
	print("[load] TownBoot.from_town (GD.load_all and the people): %.1f ms" % [float(Time.get_ticks_usec() - t) / 1000.0])
	t = Time.get_ticks_usec()
	var n := TownBoot.warm_pawns(d)
	print("[load] warm_pawns: %.1f ms for %d pictures" % [float(Time.get_ticks_usec() - t) / 1000.0, n])
	t = Time.get_ticks_usec()
	var tw = TownWorld.new()
	root.add_child(tw)
	tw.begin_build(d)
	var steps := 0
	var wworst := 0.0
	while true:
		var t1 := Time.get_ticks_usec()
		var fin: bool = tw.step_build(float(_arg("budget", "12")))
		wworst = maxf(wworst, float(Time.get_ticks_usec() - t1) / 1000.0)
		steps += 1
		if fin:
			break
	print("[load] TownWorld stepped: %.1f ms in %d steps (the worst %.1f ms), phases %s" % [float(Time.get_ticks_usec() - t) / 1000.0, steps, wworst, JSON.stringify(tw.build_ms)])
	t = Time.get_ticks_usec()
	var sim = (load("res://scripts/town/town_sim.gd") as GDScript).new(d, tw, FxNull.new())
	print("[load] TownSim.new: %.1f ms" % [float(Time.get_ticks_usec() - t) / 1000.0])
	sim = sim


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


# ---------------------------------------------------------------- the real game --

const TownPerfCap := preload("res://scripts/town/town_perf.gd")
const GAME_ALL := "house,street,walk,dead60,dead100,roofs,mapzoom,night,save"
## Scenes that are not in the default list: `attr` (which node costs how many draw calls, at the roofs camera), `zoom` (the number of draws and houses in view at several zooms)
var _gm
var _g_scenes: Array = []
var _g_cur := ""
var _g_state := ""
var _g_left := 0
var _g_warm := 90
var _g_frames := 300
var _g_boot_ms := 0
var _g_t0 := 0
var _g_rec := {}
var _g_route: Array = []
var _g_leg := 0
var _g_path: Array = []
var _g_path_i := 0
var _g_walk := false
var _g_rng := RandomNumberGenerator.new()
var _g_viewport_rid: RID
var _g_made: Array = []
var _g_card_frames := 0
var _g_first: Array = []
var _g_pending := 0
var _g_pending_t := 0.0
var _g_web_caps := false
var _g_t_scene := 0


func _game_start() -> void:
	_g_scenes = _arg("scenes", GAME_ALL).split(",")
	_g_web_caps = _arg("web", "") != ""
	_g_frames = int(_arg("frames", "300"))
	_g_warm = int(_arg("warm", "90"))
	_g_t0 = Time.get_ticks_msec()
	_g_rng.seed = 11
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_g_viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_g_viewport_rid, true)
	Engine.set_meta("run", {"town": true, "difficulty": 1, "seed": int(_arg("seed", "1")), "avatar": true})
	print("== game bench: engine up at %d ms, display %s" % [_g_t0, DisplayServer.get_name()])
	_gm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_gm)
	_g_state = "boot"


## The tile a scenario starts on: the crossing of the two middle roads.
func _g_cross() -> Vector2:
	return Vector2(94.5, 94.5)


func _g_teleport(at: Vector2) -> void:
	var me = _gm.sim.avatar.player()
	me.x = at.x
	me.y = at.y
	_gm.cam_center = at


func _g_set_route(route: Array) -> void:
	_g_route = route
	_g_leg = 0
	_g_path = []
	_g_path_i = 0


## The wave's dead come in as the rules bring them: two or three every half second or so, at the entrances of the base.
func _g_spawn_wave(delta: float) -> void:
	if _g_pending <= 0:
		return
	_g_pending_t -= delta
	if _g_pending_t > 0.0:
		return
	_g_pending_t = 0.5 + _g_rng.randf() * 0.4
	var sim = _gm.sim
	var spawns: Array = sim.spawns
	var me = sim.avatar.player()
	for i in mini(_g_pending, 2 + _g_rng.randi() % 2):
		var at: Vector2 = spawns[_g_rng.randi() % spawns.size()] if not spawns.is_empty() else Vector2(me.x + 30.0, me.y)
		var z = sim.spawn(at.x + _g_rng.randf_range(-1.0, 1.0), at.y + _g_rng.randf_range(-1.0, 1.0), "approach", "walker" if _g_rng.randf() < 0.9 else "runner")
		_g_made.append(z)
		_g_pending -= 1


## Moves the avatar along the walking grid by hand (the game's own keys are not pressed), invulnerable.
func _g_walk_step(delta: float) -> void:
	var sim = _gm.sim
	var me = sim.avatar.player()
	me.hp = 100.0
	me.downed = false
	_g_spawn_wave(delta)
	if not _g_walk or _g_route.is_empty():
		return
	if _g_path_i >= _g_path.size():
		_g_leg = (_g_leg + 1) % (_g_route.size() - 1)
		var tgt: Vector2 = _g_route[_g_leg + 1]
		_g_path = sim.path_p.find(_gm.world.solid_p, me.x, me.y, tgt.x, tgt.y)
		_g_path_i = 0
		if _g_path.is_empty():
			_g_path = [tgt]
	var wp: Vector2 = _g_path[_g_path_i]
	var to := wp - Vector2(me.x, me.y)
	var step := 4.6 * delta
	if to.length() <= step:
		me.x = wp.x
		me.y = wp.y
		_g_path_i += 1
	else:
		var d := to.normalized() * step
		me.x += d.x
		me.y += d.y


func _g_chasers(n: int) -> void:
	var sim = _gm.sim
	var me = sim.avatar.player()
	var world = _gm.world
	var made := 0
	var tries := 0
	while made < n and tries < n * 100:
		tries += 1
		var p := Vector2(me.x, me.y) + Vector2.from_angle(_g_rng.randf() * TAU) * _g_rng.randf_range(6.0, 26.0)
		if world.is_solid(world.solid_z, p.x, p.y):
			continue
		var z = sim.spawn(p.x, p.y, "wander", "walker" if _g_rng.randf() < 0.85 else "runner")
		sim.start_chase(z, me)
		z.repath = _g_rng.randf()
		_g_made.append(z)
		made += 1


func _g_zoom(px: float) -> void:
	_gm.zoom_px = px


func _g_begin_scene(name: String) -> void:
	_g_cur = name
	_g_walk = false
	var sim = _gm.sim
	if not (name == "attr" and _arg("attr_here", "") != ""):
		for z in _g_made:
			z.remove = true
		_g_made.clear()
		_gm.speed = 1
	_g_t_scene = Time.get_ticks_msec()
	if sim.get("finds_max") != null:
		sim.finds_max = 0
	var vp: Vector2 = _gm._vp()
	match name:
		"house":
			pass
		"street":
			_g_teleport(_g_cross())
		"walk":
			_g_teleport(_g_cross())
			_g_set_route([Vector2(94.5, 94.5), Vector2(126.5, 94.5), Vector2(126.5, 126.5), Vector2(94.5, 126.5), Vector2(94.5, 94.5)])
			_g_walk = true
		"dead60", "dead100":
			_g_teleport(_g_cross())
			sim.field.active_cap = 200
			_g_chasers(60 if name == "dead60" else 100)
			_g_set_route([Vector2(94.5, 94.5), Vector2(126.5, 94.5), Vector2(126.5, 126.5), Vector2(94.5, 126.5), Vector2(94.5, 94.5)])
			_g_walk = true
		"night":
			# the first attack night of the town (stage "night": a claimed house, four survivors) with the wave made as big as the rules allow (CAP_NIGHT 50 dead that come
			# at the doors) on top of the street's own dead that are awake near the base (the active cap)
			sim.field.active_cap = TownPerfCap.desktop_cap() if not _g_web_caps else TownPerfCap.web_cap()
			OneHouse.stage_to(sim, "night")
			sim.minutes = 19.5 * 60.0
			_g_pending = 50
			_g_pending_t = 0.0
			sim.field.night_mult = 1.4
			_g_zoom(maxf(vp.x / 26.0, 28.0))
		"roofs":
			_g_teleport(_g_cross())
			_g_zoom(maxf(14.0, vp.x / 84.0))
		"mapzoom":
			_g_teleport(Vector2(96, 96))
			_g_zoom(_gm._min_zoom())
		"attr":
			if _arg("attr_here", "") == "":
				_g_teleport(_g_cross())
				_g_zoom(maxf(14.0, vp.x / 84.0))
			_g_attr_start()
			return
		"zoom":
			_g_teleport(_g_cross())
			_g_zoom_i = -1
			_g_zoom_n = 0
			_g_attr_acc = 0.0
			_g_state = "zoom"
			return
		"parts":
			_g_parts_report()
			_g_scenes.pop_front()
			_g_state = "next"
			return
		"adapt":
			_g_adapt_report()
			_g_scenes.pop_front()
			_g_state = "next"
			return
		"save":
			_g_save_report()
			_g_scenes.pop_front()
			_g_state = "next"
			return
	_g_state = "warm"
	_g_left = _g_warm
	if name == "night":
		_g_left = 1000000
	_g_rec = {"n": 0, "wall": PackedFloat64Array(), "proc": 0.0, "cpu": 0.0, "gpu": 0.0, "calls": PackedFloat64Array(), "objs": 0.0, "prims": 0.0, "nodes": 0, "zs": 0.0, "awake": 0.0, "pawns": 0.0, "wave": 0.0, "pfsum": {}}
	_g_pf_take()


## The night's own dead: the ones with no record in the field (the wave's).
func _g_wave_dead() -> int:
	var sim = _gm.sim
	var c := 0
	for z in sim.zombies:
		if (z.state == "approach" or z.state == "attack" or z.state == "breach") and not sim.field.rec_of.has(z):
			c += 1
	return c


## Draw calls by node: the nodes that make up the picture are hidden one at a time at the roofs camera and the fall in draw calls is the node's share.
var _g_attr_nodes: Array = []
var _g_attr_i := -2
var _g_attr_acc := 0.0
var _g_attr_n := 0
var _g_attr_base := 0.0
var _g_attr_out: Array = []


func _g_attr_start() -> void:
	_g_attr_nodes = []
	var th: PackedInt32Array = _gm.sim.town_data.tile_house
	var wd: int = _gm.world.W
	for key in _gm.world.layers:
		var layer: Node2D = _gm.world.layers[key]
		var inside := 0
		for c in layer.get_children():
			var tile := Vector2i(floori(c.position.x / 64.0), floori(c.position.y / 64.0))
			if tile.x >= 0 and tile.y >= 0 and tile.x < wd and tile.y * wd + tile.x < th.size() and th[tile.y * wd + tile.x] >= 0:
				inside += 1
		print("[attr    ] world layer %s: %d nodes, %d of them inside a house" % [layer.name, layer.get_child_count(), inside])
	var hv = _gm.town.part("house_view")
	for n in _gm.world.get_children():
		_g_attr_nodes.append(["world/" + String(n.name), n])
	for n in _gm.get_children():
		if n is CanvasLayer:
			_g_attr_nodes.append(["layer %d %s" % [n.layer, String(n.name)], n])
	if hv != null:
		_g_attr_nodes.append(["house_view/roofs", hv._roof_layer])
		_g_attr_nodes.append(["house_view/doors", hv._door_layer])
		_g_attr_nodes.append(["house_view/veils", hv._veil_layer])
	_g_attr_nodes.append(["entities (pawns, trees)", _gm.entities])
	_g_attr_i = -1
	_g_attr_n = 0
	_g_attr_acc = 0.0
	_g_attr_out = []
	_g_state = "attr"


func _g_attr_frame() -> void:
	_g_attr_n += 1
	if _g_attr_n <= 6:
		return
	_g_attr_acc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if _g_attr_n < 26:
		return
	var avg := _g_attr_acc / 20.0
	if _g_attr_i == -1:
		_g_attr_base = avg
		print("[attr    ] draw calls all on: %.0f (objects %.0f)" % [avg, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	else:
		var e: Array = _g_attr_nodes[_g_attr_i]
		print("[attr    ]   %-34s %4.0f draw calls" % [e[0], _g_attr_base - avg])
		e[1].visible = true
	_g_attr_i += 1
	_g_attr_n = 0
	_g_attr_acc = 0.0
	if _g_attr_i >= _g_attr_nodes.size():
		_g_scenes.pop_front()
		_g_state = "next"
		return
	_g_attr_nodes[_g_attr_i][1].visible = false


var _g_zoom_i := -1
var _g_zoom_n := 0
var _g_zoom_list := [49.0, 32.0, 24.0, 18.0, 14.0, 11.0, 8.0, 0.0]


func _g_zoom_frame() -> void:
	_g_zoom_n += 1
	if _g_zoom_n <= 8:
		return
	_g_attr_acc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if _g_zoom_n < 28 and _g_zoom_i >= 0:
		return
	if _g_zoom_i >= 0:
		var view: Rect2 = _gm.view_rect()
		var hv = _gm.town.part("house_view")
		var seen := 0
		for h in hv._roofs:
			if view.intersects(Rect2(hv._house_dict(int(h)).rect)):
				seen += 1
		print("[zoom    ] %5.1f px a tile: view %.0f x %.0f tiles, %d houses in view, draw calls %.0f, objects %.0f" % [_gm.zoom_px, view.size.x, view.size.y, seen, _g_attr_acc / 20.0, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	_g_zoom_i += 1
	_g_zoom_n = 0
	_g_attr_acc = 0.0
	if _g_zoom_i >= _g_zoom_list.size():
		_g_scenes.pop_front()
		_g_state = "next"
		return
	var z: float = _g_zoom_list[_g_zoom_i]
	_g_zoom(_gm._min_zoom() if z <= 0.0 else z)


## The per-section times of a frame, when the game build has the profiling marks (a local, temporary patch of main.gd's `_process`; the real file has none): else nothing.
func _g_pf_take() -> Dictionary:
	if _gm.has_method("pf_take"):
		return _gm.pf_take()
	return {}


func _g_awake(sim) -> int:
	var c := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			c += 1
	return c


func _process(delta: float) -> bool:
	if _g_state == "":
		return false
	return _game_frame(delta)


func _game_frame(delta: float) -> bool:
	match _g_state:
		"boot":
			if _arg("cardshot", "") != "" and _gm.get_node_or_null("TownLoading") != null:
				_g_card_frames += 1
				if _g_card_frames == int(_arg("cardframe", "25")):
					root.get_viewport().get_texture().get_image().save_png(_arg("cardshot", ""))
			if _gm.sim == null or _gm.camera == null or _gm.get_node_or_null("TownLoading") != null or not _gm.is_processing():
				return false
			if _g_boot_ms == 0:
				_g_boot_ms = Time.get_ticks_msec() - _g_t0
				print("game ready %d ms after the engine was up (%d ms of the process)" % [_g_boot_ms, Time.get_ticks_msec()])
				print("main's own load phases (ms): %s" % JSON.stringify(_gm.get("load_ms")))
				_g_state = "settle"
				_g_left = 30
				if int(_arg("firstframes", "0")) > 0:
					_g_state = "first"
					_g_left = int(_arg("firstframes", "0"))
					_g_first = []
			return false
		"first":
			var pfn: Dictionary = _g_pf_take()
			var tot := 0.0
			var topk := ""
			var bestv := 0.0
			for k in pfn:
				tot += pfn[k] / 1000.0
				if pfn[k] / 1000.0 > bestv:
					bestv = pfn[k] / 1000.0
					topk = k
			_g_first.append([delta * 1000.0, tot, topk, bestv])
			_g_left -= 1
			if _g_left <= 0:
				var line := []
				for i in _g_first.size():
					line.append("%.0f" % _g_first[i][0])
				print("[first   ] wall ms of the first %d frames after the card: %s" % [_g_first.size(), " ".join(line)])
				var worst := _g_first.duplicate()
				worst.sort_custom(func(a, b): return a[1] > b[1])
				for i in mini(6, worst.size()):
					print("[first   ]   scripts %.1f ms (most in %s: %.1f), wall %.1f ms" % [worst[i][1], worst[i][2], worst[i][3], worst[i][0]])
				_g_state = "settle"
				_g_left = 30
			return false
		"settle":
			_g_left -= 1
			if _g_left <= 0:
				_g_state = "next"
			return false
		"next":
			if _g_scenes.is_empty():
				print("== done")
				return true
			_g_begin_scene(String(_g_scenes[0]))
			return false
		"warm":
			_g_walk_step(delta)
			_g_left -= 1
			if _g_cur == "night" and _g_pending <= 0 and Time.get_ticks_msec() - _g_t_scene > 40000:
				_g_left = 0
			if _g_left <= 0:
				_g_state = "run"
				_g_left = _g_frames
				_g_pf_take()
			return false
		"attr":
			_g_attr_frame()
			return false
		"zoom":
			_g_zoom_frame()
			return false
		"run":
			_g_walk_step(delta)
			var r: Dictionary = _g_rec
			r.n += 1
			r.wall.append(delta * 1000.0)
			if _arg("spikes", "") != "":
				var pfn: Dictionary = _g_pf_take()
				var total := 0.0
				var top := ""
				var best := 0.0
				for k in pfn:
					total += pfn[k] / 1000.0
					if pfn[k] / 1000.0 > best:
						best = pfn[k] / 1000.0
						top = k
					r.pfsum[k] = float(r.pfsum.get(k, 0.0)) + pfn[k]
				if total > float(_arg("spikes", "6")):
					print("  spike in [%s] frame %d: scripts %.1f ms (most: %s %.1f), wall %.1f ms" % [_g_cur, r.n, total, top, best, delta * 1000.0])
			r.proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			r.cpu += RenderingServer.viewport_get_measured_render_time_cpu(_g_viewport_rid)
			r.gpu += RenderingServer.viewport_get_measured_render_time_gpu(_g_viewport_rid)
			r.calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			r.objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			r.prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			r.nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			r.zs += _gm.sim.zombies.size()
			r.awake += _g_awake(_gm.sim)
			r.wave += _g_wave_dead()
			r.pawns += _gm.pawn_nodes.size()
			_g_left -= 1
			if _g_left <= 0:
				_g_report()
				_g_scenes.pop_front()
				_g_state = "next"
			return false
	return false


func _g_report() -> void:
	var r: Dictionary = _g_rec
	if _arg("debug_hud", "") != "":
		var th = _gm.town.part("town_hud")
		print("DEBUG hud bearing %s distance %s body %s zoom %s cam %s" % [th.bearing, th.distance, th._avatar_body(), _gm.zoom_px, _gm.cam_center])
	var n := float(maxi(1, r.n))
	var w: PackedFloat64Array = r.wall
	w.sort()
	var calls: PackedFloat64Array = r.calls
	var csum := 0.0
	var cmax := 0.0
	for c in calls:
		csum += c
		cmax = maxf(cmax, c)
	var wsum := 0.0
	for v in w:
		wsum += v
	var pf: Dictionary = r.pfsum if not r.pfsum.is_empty() else _g_pf_take()
	var parts := []
	for k in pf:
		parts.append("%s %.2f" % [k, pf[k] / 1000.0 / n])
	var town = _gm.town
	var hv = town.part("house_view") if town != null else null
	print("[%-8s] zoom %.1f px, camera %s, avatar %s, day %d hour %.2f, speed %d" % [_g_cur, _gm.zoom_px, _gm.cam_center, Vector2(_gm.sim.avatar.player().x, _gm.sim.avatar.player().y), _gm.sim.day, _gm.sim.hour, _gm.speed])
	print("[%-8s] frames %d | wall ms: mean %.2f p50 %.2f p95 %.2f p99 %.2f max %.2f | process %.2f render cpu %.2f gpu %.2f | draws mean %.0f max %.0f objs %.0f | nodes %d, pawn nodes %.0f, zombies %.0f (awake %.0f, wave %.0f), roof/door/veil nodes %d" % [_g_cur, r.n, wsum / n, w[int(w.size() / 2)], w[int(w.size() * 0.95)], w[int(w.size() * 0.99)], w[w.size() - 1], r.proc / n, r.cpu / n, r.gpu / n, csum / n, cmax, r.objs / n, r.nodes, r.pawns / n, r.zs / n, r.awake / n, r.wave / n, hv.node_count() if hv != null else -1])
	var perf = _gm.town.get("perf") if _gm.town != null else null
	print("           %spath finds per step max %d | active cap %s" % [("main sections ms/frame: %s | " % " | ".join(parts)) if not parts.is_empty() else "", int(_gm.sim.get("finds_max") if _gm.sim.get("finds_max") != null else -1), str(perf.cap) if perf != null else "-"])


## What each view part of the town costs a frame (its `on_frame` and `on_sync_views`), by calling them 300 times in the state the game is in.
func _g_parts_report() -> void:
	var town = _gm.town
	var view: Rect2 = _gm.view_rect().grow(3.0)
	var rows := []
	for part in town.parts:
		var name := String(part.get_script().resource_path.get_file())
		var t := Time.get_ticks_usec()
		if part.has_method("on_frame"):
			for i in 300:
				part.on_frame(0.0167)
		var f_us := float(Time.get_ticks_usec() - t) / 300.0
		t = Time.get_ticks_usec()
		if part.has_method("on_sync_views"):
			for i in 300:
				part.on_sync_views(view)
		var s_us := float(Time.get_ticks_usec() - t) / 300.0
		rows.append("%s on_frame %.0f us, on_sync_views %.0f us" % [name, f_us, s_us])
	var t2 := Time.get_ticks_usec()
	for i in 300:
		town.on_frame(0.0167)
	rows.append("facade on_frame in all %.0f us" % [float(Time.get_ticks_usec() - t2) / 300.0])
	print("[parts   ] %s" % "\n           ".join(rows))


## The adaptive cap (scripts/town/town_perf.gd) driven with made-up frame times on the live game: 60 awake dead, frames of 40 ms for 3 s (the cap halves), 20 ms (nothing), 12 ms for
## 6 s (it comes back by halves of the way).
func _g_adapt_report() -> void:
	var sim = _gm.sim
	var perf = _gm.town.perf
	perf.enabled = false
	sim.field.active_cap = 200
	_g_made.clear()
	var me = sim.avatar.player()
	_g_teleport(_g_cross())
	_g_chasers(0)
	for i in 70:
		var z = sim.spawn(me.x + _g_rng.randf_range(-20.0, 20.0), me.y + _g_rng.randf_range(-20.0, 20.0), "wander", "walker")
		_g_made.append(z)
	var full: int = perf.full
	perf.cap = full
	sim.field.active_cap = full
	var lines := []
	var t := 0.0
	for phase in [["40 ms frames", 0.040, 3.0], ["20 ms frames", 0.020, 4.0], ["12 ms frames", 0.012, 12.0]]:
		var n := int(float(phase[2]) / float(phase[1]))
		for i in n:
			perf.step(float(phase[1]))
			t += float(phase[1])
			if i % maxi(1, n / 6) == 0 or i == n - 1:
				lines.append("%s t=%.1fs avg %.1f ms cap %d" % [phase[0], t, perf.avg_ms, perf.cap])
		sim.update(1.0 / 30.0)
		lines.append("  after the %s: cap %d, awake of the field %d, halved %d restored %d" % [phase[0], perf.cap, sim.field.active_of.size(), perf.halved, perf.restored])
	print("[adapt   ] %s" % "\n           ".join(lines))
	perf.enabled = true


## A save of the game as it is (the real sim, a mid-game town: the stage "night" is four survivors and a claimed house): the size and the times of saving and of loading.
func _g_save_report() -> void:
	var sim = _gm.sim
	var t := Time.get_ticks_usec()
	sim.pre_save()
	var us_pre := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var data: Dictionary = SaveGame.to_dict(sim)
	var us_dict := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var text: String = SaveGame.to_text(data)
	var us_text := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var parsed: Dictionary = SaveGame.from_text(text)
	var us_parse := Time.get_ticks_usec() - t
	var path := _arg("savepath", "user://bench_town_save.json")
	t = Time.get_ticks_usec()
	var ok: bool = SaveGame.write(sim, path)
	var us_write := Time.get_ticks_usec() - t
	var size := 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		size = int(f.get_length())
		f.close()
	t = Time.get_ticks_usec()
	var back: Dictionary = SaveGame.read(path)
	var us_read := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var applied: bool = SaveGame.apply(sim, back)
	var us_apply := Time.get_ticks_usec() - t
	print("[save    ] %d bytes (%.1f KB) | save: pre_save %.1f ms + to_dict %.1f + to_text %.1f + (check: from_text %.1f) = SaveGame.write %.1f ms (ok %s) | load: read+parse %.1f ms + apply %.1f ms (ok %s)" % [size, float(size) / 1024.0, float(us_pre) / 1000.0, float(us_dict) / 1000.0, float(us_text) / 1000.0, float(us_parse) / 1000.0, float(us_write) / 1000.0, ok, float(us_read) / 1000.0, float(us_apply) / 1000.0, applied])
	var modules = parsed.get("modules", {})
	var rows := []
	for k in modules:
		rows.append([JSON.stringify(modules[k]).length(), String(k)])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var top := []
	for i in mini(8, rows.size()):
		top.append("%s %d" % [rows[i][1], rows[i][0]])
	var rest := []
	for k in parsed:
		if k != "modules":
			rest.append("%s %d" % [k, JSON.stringify(parsed[k]).length()])
	print("           bytes of JSON by module: %s | other top keys: %s" % [", ".join(top), ", ".join(rest)])
