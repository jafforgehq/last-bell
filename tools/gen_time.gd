## How long the town takes to make (WORLD3): each seed is made `--reps` times and the least time of them is kept (a busy machine only ever adds), with the phases of that make.
##
##   godot --headless --path . --script res://tools/gen_time.gd -- --seeds=1..4 [--reps=8]
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var seeds: Array = []
	var reps := 8
	for a in OS.get_cmdline_user_args():
		var t := String(a)
		if t.begins_with("--seeds="):
			var parts := t.trim_prefix("--seeds=").split("..")
			for s in range(int(parts[0]), int(parts[parts.size() - 1]) + 1):
				seeds.append(s)
		elif t.begins_with("--reps="):
			reps = int(t.trim_prefix("--reps="))
	if seeds.is_empty():
		seeds = [1, 2, 3]
	var total := 0.0
	var phase_sum := {}
	for sd in seeds:
		var best := 1.0e12
		var best_phases := {}
		for r in reps:
			var t0 := Time.get_ticks_usec()
			var town: Dictionary = TownGen.make(int(sd), {"blocks": 6})
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			if ms < best:
				best = ms
				best_phases = (town.stats.get("ms", {}) as Dictionary).duplicate()
		total += best
		for k in best_phases:
			phase_sum[k] = float(phase_sum.get(k, 0.0)) + float(best_phases[k])
		print("seed %d: best %.1f ms of %d" % [int(sd), best, reps])
	var avg := total / float(seeds.size())
	var shown := {}
	for k in phase_sum:
		shown[k] = snappedf(float(phase_sum[k]) / float(seeds.size()), 0.1)
	print("GEN_TIME mean of the bests %.1f ms; phases %s" % [avg, JSON.stringify(shown)])
	quit()
