## Audit evidence (2026-10-01): Pathfinder cost on city-sized grids.
## Compares raw AStarGrid2D time with Pathfinder.find() (A* plus string-pulling smoothing).
##   Godot --headless --path . --script docs/audit/evidence/bench_path.gd
extends SceneTree

const Pathfinder := preload("res://scripts/sim/pathfinder.gd")


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	print("size        tiles    build ms   update ms   long path ms (avg of 40)   short path ms (avg of 200)")
	for dims in [Vector2i(84, 64), Vector2i(168, 128), Vector2i(252, 192), Vector2i(336, 256)]:
		var w: int = dims.x
		var h: int = dims.y
		var solid := PackedByteArray()
		solid.resize(w * h)
		# city blocks: rectangles of buildings 10x7 every 16x12 with streets between, plus random clutter
		for by in range(2, h - 8, 12):
			for bx in range(2, w - 12, 16):
				for y in range(by, by + 7):
					for x in range(bx, bx + 10):
						solid[y * w + x] = 1
		for i in int(w * h * 0.03):
			solid[rng.randi() % (w * h)] = 1
		solid[0] = 0
		solid[w * h - 1] = 0
		var t0 := Time.get_ticks_usec()
		var pf = Pathfinder.new(w, h, solid)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		pf.grid.update()
		var upd_ms := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var okc := 0
		for i in 40:
			var a := Vector2(1.5 + rng.randf() * 3.0, 1.5 + rng.randf() * 3.0)
			var b := Vector2(w - 2.5 - rng.randf() * 3.0, h - 2.5 - rng.randf() * 3.0)
			var p: Array = pf.find(solid, a.x, a.y, b.x, b.y)
			if not p.is_empty():
				okc += 1
		var long_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 40.0
		t0 = Time.get_ticks_usec()
		var raw_len := 0
		for i in 40:
			var a2 := Vector2i(1 + (i % 4), 1 + (i % 3))
			var b2 := Vector2i(w - 2 - (i % 4), h - 2 - (i % 3))
			raw_len += pf.grid.get_id_path(a2, b2).size()
		var raw_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 40.0
		print("   raw A* only, corner to corner: %.2f ms avg, path length %d cells" % [raw_ms, raw_len / 40])
		t0 = Time.get_ticks_usec()
		for i in 200:
			var a := Vector2(rng.randf() * (w - 2) + 1.0, rng.randf() * (h - 2) + 1.0)
			var b := a + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))
			b = Vector2(clampf(b.x, 1.0, w - 2.0), clampf(b.y, 1.0, h - 2.0))
			pf.find(solid, a.x, a.y, b.x, b.y)
		var short_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 200.0
		print("%3dx%-3d  %8d  %9.1f  %10.1f  %12.2f (found %d/40)     %12.3f" % [w, h, w * h, build_ms, upd_ms, long_ms, okc, short_ms])
	quit()
