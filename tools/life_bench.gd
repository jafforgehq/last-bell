## What the base's little life (round 24, scripts/render/base_life.gd) costs, measured in a real window: the real game's scene is run with the
## arguments you give and the life is switched on and off in blocks of ten frames (the first four frames of a block are not counted: the renderer reports a frame or two late), so that the two are measured
## under the same smoke, the same people and the same drift of the machine (a hitch of the machine lands on both). For each frame it reads the draw calls the renderer made
## (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`), the script time (`TIME_PROCESS`, ms)
## and the renderer's CPU time (ms), and prints the averages for "life on" and "life off" and the difference. The middle (median) of the script
## time is printed too, because one hitch (a load, a garbage run) can swell an average.
## Windowed (headless draws nothing), from the repo root:
##
##   Godot --path . --script res://tools/life_bench.gd -- --new=1 --crew=3 --seed=5 --hour=11 --cam=42,30,36 [--frames=600] [--size=1280x800]
##
## The arguments are the ones main.gd takes (see the README's table; `--weather=rain` and `--hour=21` for the rain's ripples and the night's glow);
## `--frames=N` (default 600) frames are measured after a warm-up of 120.
extends SceneTree

const WARM := 120
const BLOCK := 10
const SKIP := 4

var _main: Node
var _frame := 0
var _frames := 600
var _last_on := true
var _calls := [[], []]
var _proc := [[], []]
var _cpu := [[], []]


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return default


func _initialize() -> void:
	_frames = int(_arg("frames", "600"))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _process(_delta: float) -> bool:
	if _main == null or _main.get("life_view") == null:
		return false
	_frame += 1
	if _frame <= WARM:
		return false
	if _frame > WARM + _frames:
		_report()
		quit()
		return true
	var block := (_frame - WARM - 1) / BLOCK
	var at := (_frame - WARM - 1) % BLOCK
	var on := block % 2 == 0
	if at >= SKIP and on == _last_on:
		var i := 0 if on else 1
		_calls[i].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_proc[i].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_cpu[i].append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
	if at == 0:
		_last_on = on
		_main.life_view.set_enabled(on)
	return false


static func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, float(a.size()))


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2]) if not b.is_empty() else 0.0


func _report() -> void:
	print("life_bench: %d frames measured, life on %d, off %d" % [_frames, _calls[0].size(), _calls[1].size()])
	print("  draw calls   on %.1f   off %.1f   difference %+.1f" % [_mean(_calls[0]), _mean(_calls[1]), _mean(_calls[0]) - _mean(_calls[1])])
	print("  script ms    on %.3f   off %.3f   difference %+.3f   (median on %.3f, off %.3f)" % [_mean(_proc[0]), _mean(_proc[1]), _mean(_proc[0]) - _mean(_proc[1]), _median(_proc[0]), _median(_proc[1])])
	print("  render cpu   on %.3f   off %.3f   difference %+.3f   (median on %.3f, off %.3f)" % [_mean(_cpu[0]), _mean(_cpu[1]), _mean(_cpu[0]) - _mean(_cpu[1]), _median(_cpu[0]), _median(_cpu[1])])
