## What a big fight costs to draw (P-COMBAT): the real game's scene in a real window, the avatar firing steadily at about sixty of the dead in
## view (as many again lie where they fell), measured frame by frame: the script time (`TIME_PROCESS`, ms), the renderer's CPU time (ms), the draw
## calls and the frame time, with their averages, medians and 95th percentiles. The same script runs on the game before the feel (it only uses
## what both have), so the two numbers can be set side by side; on this game it also counts the effects made.
## Windowed (headless draws nothing), from the repository root:
##
##   Godot --path . --script res://tools/combat_bench.gd -- --town --stage=night --avatar-at=114.5,55.5 [--frames=600] [--dead=60] [--weapon=shotgun]
##
## (the dead are put south of the avatar, in the street; in the school game give --new=1 --seed=3 --crew=5 --night=ordinary --hour=22 instead)
##
## The arguments are the ones main.gd takes; `--frames=N` frames are measured after 150 of warming up, `--dead=N` is how many of the dead are kept coming,
## `--weapon=<id>` the gun (the rifle: the one in the avatar's hands is changed whatever the pawn's picture shows).
extends SceneTree

const WARM := 150

var _main: Node
var _frame := 0
var _frames := 600
var _dead := 60
var _weapon := "rifle"
var _proc: Array = []
var _cpu: Array = []
var _calls: Array = []
var _ms: Array = []
var _live: Array = []
var _last_us := 0
var _rng := RandomNumberGenerator.new()


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return default


func _initialize() -> void:
	_frames = int(_arg("frames", "600"))
	_dead = int(_arg("dead", "60"))
	_weapon = _arg("weapon", "rifle")
	_rng.seed = 11
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


## The living dead nearest the avatar (null when none).
func _nearest(me):
	var best = null
	var best_d := INF
	for z in _main.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var d := Vector2(z.x - me.x, z.y - me.y).length()
		if d < best_d:
			best_d = d
			best = z
	return best


func _feed() -> void:
	var sim = _main.sim
	var me = sim.avatar.player()
	if me == null:
		return
	sim.stock.ammo = 5000.0
	if _frame == 2:
		me.weapon = _weapon
		me.gun = sim.weapons[_weapon]
		me.mag = int(me.gun.get("mag", 0))
		# a field of the fallen already (they lie there for the minute the run lasts): about a third as many as the living
		for i in _dead / 3:
			var at := Vector2(me.x - 6.0 + _rng.randf() * 12.0, me.y + 2.5 + _rng.randf() * 8.0)
			if not _main.world.is_solid(_main.world.solid_z, at.x, at.y):
				var c = sim.spawn(at.x, at.y, "wander", "walker")
				c.state = "dead"
				c.fall = 1.0
				c.fall_dir = 1.0 if _rng.randf() < 0.5 else -1.0
				c.dead_t = 0.0
				c.hp = 0.0
	# keep the field full of the dead: a ring of them east of the wall, coming for it
	var alive := 0
	for z in sim.zombies:
		if z.state != "dying" and z.state != "dead":
			alive += 1
	var kinds := ["walker", "walker", "walker", "runner", "brute"]
	while alive < _dead:
		var at := Vector2(me.x - 6.0 + _rng.randf() * 12.0, me.y + 3.0 + _rng.randf() * 7.0)
		if _main.world.is_solid(_main.world.solid_z, at.x, at.y):
			alive += 1    # (a spot in a wall: skip it, but do not spin)
			continue
		var z = sim.spawn(at.x, at.y, "approach", kinds[_rng.randi() % kinds.size()])
		z.facing = "W"
		alive += 1
	var target = _nearest(me)
	if target != null:
		_main.shot_aim = Vector2(target.x, target.y - 0.3)
		_main.mouse_screen = _main._tile_to_screen(_main.shot_aim)
	_main.firing = true
	_main.aim_held = true
	_main.shot_aiming = true


func _process(_delta: float) -> bool:
	if _main == null or _main.get("sim") == null:
		return false
	_frame += 1
	_feed()
	if _frame <= WARM:
		return false
	if _frame > WARM + _frames:
		_report()
		quit()
		return true
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_ms.append(float(now - _last_us) / 1000.0)
	_last_us = now
	_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
	var fx = _main.get("fx")
	if fx != null and fx.get("combat") != null:
		_live.append(fx.combat.live_count())
	return false


static func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, float(a.size()))


static func _pct(a: Array, p: float) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[mini(b.size() - 1, int(float(b.size()) * p))]) if not b.is_empty() else 0.0


func _report() -> void:
	var sim = _main.sim
	var down := 0
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			down += 1
	print("combat_bench: %d frames, %s, kills %d, the dead on the ground %d, %d on their feet" % [_frames, _weapon, sim.kills, down, sim.zombies.size() - down])
	print("  frame ms      mean %.2f   median %.2f   p95 %.2f   worst %.2f   (%.0f fps)" % [_mean(_ms), _pct(_ms, 0.5), _pct(_ms, 0.95), _pct(_ms, 1.0), 1000.0 / maxf(_mean(_ms), 0.001)])
	print("  script ms     mean %.3f   median %.3f   p95 %.3f" % [_mean(_proc), _pct(_proc, 0.5), _pct(_proc, 0.95)])
	print("  render cpu ms mean %.3f   median %.3f   p95 %.3f" % [_mean(_cpu), _pct(_cpu, 0.5), _pct(_cpu, 0.95)])
	print("  draw calls    mean %.1f   median %.1f   p95 %.1f" % [_mean(_calls), _pct(_calls, 0.5), _pct(_calls, 0.95)])
	if not _live.is_empty():
		print("  effects alive mean %.1f   most %d" % [_mean(_live), int(_pct(_live, 1.0))])
