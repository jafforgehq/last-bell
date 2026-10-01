extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const Pathfinder := preload("res://scripts/sim/pathfinder.gd")


# ------------------------------------------------------------- test grids --

## A random grid: every cell solid with chance `density`, plus a few blocks.
func _grid(rng: RandomNumberGenerator, w: int, h: int, density: float) -> PackedByteArray:
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		if rng.randf() < density:
			solid[i] = 1
	for k in 3:
		var bx := rng.randi_range(0, w - 4)
		var by := rng.randi_range(0, h - 4)
		for y in range(by, mini(h, by + rng.randi_range(1, 3))):
			for x in range(bx, mini(w, bx + rng.randi_range(2, 6))):
				solid[y * w + x] = 1
	return solid


## The cell (x, y) of a random free cell, or (-1, -1) if there is none.
func _free_cell(rng: RandomNumberGenerator, w: int, h: int, solid: PackedByteArray) -> Vector2i:
	for k in 1000:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		if solid[y * w + x] == 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


func _length(from: Vector2, path: Array) -> float:
	var total := 0.0
	var at := from
	for p in path:
		total += at.distance_to(p)
		at = p
	return total


# ------------------------------------- the algorithm as it was before the window --
# A copy of the old sight, smooth and find, to hold the new ones to.

func _ref_free(pf, solid: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < pf.W and y < pf.H and solid[y * pf.W + x] == 0


func _ref_sight(pf, solid: PackedByteArray, a: Vector2, b: Vector2, r: float = 0.3) -> bool:
	var dv := b - a
	var dist := dv.length()
	var n := maxi(1, ceili(dist / 0.2))
	var nrm := Vector2.ZERO if dist == 0.0 else Vector2(-dv.y, dv.x) / dist * r
	for i in n + 1:
		var p := a + dv * (float(i) / float(n))
		if not _ref_free(pf, solid, floori(p.x), floori(p.y)):
			return false
		if not _ref_free(pf, solid, floori(p.x + nrm.x), floori(p.y + nrm.y)):
			return false
		if not _ref_free(pf, solid, floori(p.x - nrm.x), floori(p.y - nrm.y)):
			return false
	return true


## {"path": what the old find returned, "points": how many points the raw path
## had (start included), "calls": how many sight checks the old smooth made}.
func _ref_find(pf, solid: PackedByteArray, sx: float, sy: float, tx: float, ty: float) -> Dictionary:
	var s = pf.nearest_free(solid, floori(sx), floori(sy))
	var t = pf.nearest_free(solid, floori(tx), floori(ty))
	if s == null or t == null:
		return {"path": [], "points": 0, "calls": 0}
	if s == t:
		return {"path": [Vector2(tx, ty)], "points": 0, "calls": 0}
	var ids: Array = pf.grid.get_id_path(s, t)
	if ids.is_empty():
		return {"path": [], "points": 0, "calls": 0}
	var pts: Array = [Vector2(sx, sy)]
	for c in ids:
		pts.append(Vector2(c.x + 0.5, c.y + 0.5))
	pts[pts.size() - 1] = Vector2(tx, ty)
	var calls := 0
	var out: Array = [pts[0]]
	if pts.size() >= 3:
		var i := 0
		while i < pts.size() - 1:
			var j := pts.size() - 1
			while j > i + 1:
				calls += 1
				if _ref_sight(pf, solid, pts[i], pts[j]):
					break
				j -= 1
			out.append(pts[j])
			i = j
	else:
		out = pts
	out.remove_at(0)
	return {"path": out, "points": pts.size(), "calls": calls}


# ------------------------------------------------------------------- tests --

func test_sight_sees_what_it_always_saw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var clear := 0
	var blocked := 0
	for g in 6:
		var w := 30 + g * 7
		var h := 24 + g * 5
		var solid := _grid(rng, w, h, 0.03 + 0.03 * g)
		var pf := Pathfinder.new(w, h, solid)
		for k in 500:
			# from anywhere, up to a tile off the map, in any direction
			var a := Vector2(rng.randf_range(-1.0, w + 1.0), rng.randf_range(-1.0, h + 1.0))
			var b := a + Vector2(rng.randf_range(-25.0, 25.0), rng.randf_range(-25.0, 25.0))
			if k % 7 == 0:
				b = a + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
			var r := 0.3 if k % 5 != 0 else rng.randf_range(0.0, 0.6)
			var now: bool = pf.sight(solid, a, b, r)
			if now != _ref_sight(pf, solid, a, b, r):
				failures.append("grid %d, line %s to %s (r %.2f): the old sight said %s" % [g, str(a), str(b), r, str(not now)])
				return
			if now:
				clear += 1
			else:
				blocked += 1
	check(clear > 200 and blocked > 200, "the lines were a fair mix: %d clear, %d blocked" % [clear, blocked])


func test_sight_counts_its_calls_and_the_caller_resets_the_count() -> void:
	var solid := PackedByteArray()
	solid.resize(100)
	var pf := Pathfinder.new(10, 10, solid)
	eq(pf.sight_calls, 0, "a new pathfinder has made none")
	pf.sight(solid, Vector2(1.5, 1.5), Vector2(8.5, 8.5))
	pf.sight(solid, Vector2(1.5, 1.5), Vector2(2.5, 1.5))
	eq(pf.sight_calls, 2, "one for each line")
	pf.sight_calls = 0
	pf.find(solid, 1.5, 1.5, 8.5, 8.5)
	check(pf.sight_calls > 0 and pf.sight_calls <= Pathfinder.LOOKAHEAD, "a find counts the checks its smoothing made: %d" % pf.sight_calls)


func test_a_smoothed_path_is_valid_and_never_longer_than_the_raw_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var found := 0
	var beyond_the_window := 0
	for g in 5:
		var w := 40 + g * 10
		var h := 30 + g * 6
		var solid := _grid(rng, w, h, 0.12 + 0.04 * g)
		var pf := Pathfinder.new(w, h, solid)
		for k in 40:
			var cs := _free_cell(rng, w, h, solid)
			var ct := _free_cell(rng, w, h, solid)
			if cs == ct or cs.x < 0 or ct.x < 0:
				continue
			var a := _center(cs)
			var b := _center(ct)
			var ids: Array = pf.grid.get_id_path(cs, ct)
			pf.sight_calls = 0
			var path: Array = pf.find(solid, a.x, a.y, b.x, b.y)
			if ids.is_empty():
				eq(path, [], "grid %d, %s to %s: no way through" % [g, str(cs), str(ct)])
				continue
			found += 1
			if ids.size() > Pathfinder.LOOKAHEAD:
				beyond_the_window += 1
			var label := "grid %d, %s to %s" % [g, str(cs), str(ct)]
			check(not path.is_empty(), "%s: a way was found" % label)
			if path.is_empty():
				continue
			check(path.size() <= ids.size(), "%s: %d points for a raw path of %d" % [label, path.size(), ids.size()])
			eq(path[path.size() - 1], b, "%s: ends at the target" % label)
			var at := a
			for p in path:
				if not pf.sight(solid, at, p):
					failures.append("%s: no line of sight from %s to %s" % [label, str(at), str(p)])
					break
				at = p
			var raw := [] # the raw path's own points, for its length
			for c in ids:
				raw.append(_center(c))
			check(_length(a, path) <= _length(a, raw) + 0.001, "%s: smoothing made the way longer" % label)
			check(pf.sight_calls <= (Pathfinder.LOOKAHEAD - 1) * ids.size(), "%s: %d sight checks for %d points" % [label, pf.sight_calls, ids.size()])
	check(found >= 100, "enough paths were tried: %d" % found)
	check(beyond_the_window >= 10, "and some were longer than the window: %d" % beyond_the_window)


func test_the_sight_checks_are_bounded_by_the_window_on_a_long_winding_path() -> void:
	# a staircase of one-cell steps: the way turns at every cell, so no point can
	# see more than a point or two ahead, and the path is 200 cells long
	var steps := 100
	var size := steps + 4
	var solid := PackedByteArray()
	solid.resize(size * size)
	solid.fill(1)
	for k in steps + 1:
		solid[k * size + k] = 0
		if k < steps:
			solid[k * size + k + 1] = 0
	var pf := Pathfinder.new(size, size, solid)
	var from := Vector2(0.5, 0.5)
	var to := Vector2(steps + 0.5, steps + 0.5)
	var ids: Array = pf.grid.get_id_path(Vector2i(0, 0), Vector2i(steps, steps))
	eq(ids.size(), 2 * steps + 1, "the way is two cells a step")
	pf.sight_calls = 0
	var path: Array = pf.find(solid, from.x, from.y, to.x, to.y)
	check(not path.is_empty(), "and there is one")
	var bound := (Pathfinder.LOOKAHEAD - 1) * ids.size()
	check(pf.sight_calls <= bound, "%d sight checks for %d points (at most %d)" % [pf.sight_calls, ids.size(), bound])
	var old := _ref_find(pf, solid, from.x, from.y, to.x, to.y)
	check(old.calls > 2 * bound, "the old way of smoothing made %d checks: the bound means something" % old.calls)
	var at := from
	for p in path:
		if not pf.sight(solid, at, p):
			failures.append("no line of sight from %s to %s" % [str(at), str(p)])
			break
		at = p
	eq(path[path.size() - 1], to, "and it ends at the target")


func test_short_paths_come_out_exactly_as_before() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var compared := 0
	var bent := 0
	for g in 8:
		var w := 24 + g * 3
		var h := 20 + g * 2
		var solid := _grid(rng, w, h, 0.08 + 0.03 * g)
		var pf := Pathfinder.new(w, h, solid)
		for k in 80:
			var cs := _free_cell(rng, w, h, solid)
			var ct := _free_cell(rng, w, h, solid)
			if cs.x < 0 or ct.x < 0:
				continue
			# anywhere inside the free cells, not only their centres
			var a := Vector2(cs.x + rng.randf(), cs.y + rng.randf())
			var b := Vector2(ct.x + rng.randf(), ct.y + rng.randf())
			var old := _ref_find(pf, solid, a.x, a.y, b.x, b.y)
			if old.points == 0 or old.points > Pathfinder.LOOKAHEAD + 1:
				continue # longer than the window: it may take a few more waypoints than before
			var now: Array = pf.find(solid, a.x, a.y, b.x, b.y)
			compared += 1
			if now.size() >= 3:
				bent += 1
			if now != old.path:
				failures.append("grid %d, %s to %s: now %s, before %s" % [g, str(a), str(b), str(now), str(old.path)])
				return
	check(compared >= 300, "enough short paths were compared: %d" % compared)
	check(bent >= 100, "and enough of them bend: %d" % bent)


func test_a_straight_run_longer_than_the_window_gets_a_waypoint_every_so_many_points() -> void:
	# on an open strip, from the middle of one tile to the middle of another along
	# the row: the raw path's points are the start, then a tile's centre each
	var w := 70
	var h := 5
	var solid := PackedByteArray()
	solid.resize(w * h)
	var pf := Pathfinder.new(w, h, solid)
	var path: Array = pf.find(solid, 1.5, 2.5, 68.5, 2.5)
	eq(path.size(), 3, "67 tiles: a waypoint 24 points on, 24 more, and the target")
	eq(path[0], Vector2(24.5, 2.5), "the first")
	eq(path[1], Vector2(48.5, 2.5), "the second")
	eq(path[2], Vector2(68.5, 2.5), "the target")
	# a path that fits in the window is one straight line, as it always was
	eq(pf.find(solid, 1.5, 2.5, 24.5, 2.5), [Vector2(24.5, 2.5)], "a path of 25 points: one line")
	eq(pf.find(solid, 1.5, 2.5, 25.5, 2.5), [Vector2(24.5, 2.5), Vector2(25.5, 2.5)], "one point more and the window ends before the target")


func test_a_corner_is_kept_and_a_straight_line_is_not() -> void:
	# a wall with a gap at its far end: the way goes round the end of it
	var w := 20
	var h := 12
	var solid := PackedByteArray()
	solid.resize(w * h)
	for x in range(0, 15):
		solid[5 * w + x] = 1
	var pf := Pathfinder.new(w, h, solid)
	var path: Array = pf.find(solid, 2.5, 2.5, 2.5, 8.5)
	check(path.size() >= 2, "the way bends round the wall: %s" % str(path))
	var at := Vector2(2.5, 2.5)
	for p in path:
		check(pf.sight(solid, at, p), "each leg is a straight line that fits: %s to %s" % [str(at), str(p)])
		at = p
	eq(path[path.size() - 1], Vector2(2.5, 8.5), "and ends at the target")
	eq(pf.find(solid, 2.5, 2.5, 17.5, 3.5).size(), 1, "with nothing in the way it is one line")


func test_no_way_gives_nothing_and_no_distance_gives_the_target() -> void:
	var w := 30
	var h := 24
	var solid := PackedByteArray()
	solid.resize(w * h)
	# a cell shut in by a ring of walls
	for x in range(13, 18):
		solid[5 * w + x] = 1
		solid[9 * w + x] = 1
	for y in range(5, 10):
		solid[y * w + 13] = 1
		solid[y * w + 17] = 1
	# a block of rock deeper than the pathfinder looks for a free tile
	for y in range(12, 24):
		for x in range(18, 30):
			solid[y * w + x] = 1
	var pf := Pathfinder.new(w, h, solid)
	eq(pf.find(solid, 2.5, 2.5, 15.5, 7.5), [], "the shut-in cell cannot be reached")
	eq(pf.find(solid, 15.5, 7.5, 2.5, 2.5), [], "nor left")
	eq(pf.find(solid, 2.5, 2.5, 24.5, 18.5), [], "nowhere near a free tile: no way")
	eq(pf.find(solid, 24.5, 18.5, 2.5, 2.5), [], "nor from there")
	eq(pf.find(solid, 4.5, 4.5, 4.5, 4.5), [Vector2(4.5, 4.5)], "already there: the target")
	eq(pf.find(solid, 4.2, 4.3, 4.7, 4.9), [Vector2(4.7, 4.9)], "in the same tile: just the target")
	check(not pf.find(solid, 2.5, 2.5, 25.5, 2.5).is_empty(), "and a way that exists is found")


func test_paths_on_the_real_map_are_valid_and_bounded() -> void:
	var g := Helpers.make(1, 1)
	var w: int = g.sim.W
	var h: int = g.sim.H
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var found := 0
	for pair in [[g.sim.path_z, g.world.solid_z], [g.sim.path_p, g.world.solid_p]]:
		var pf = pair[0]
		var solid: PackedByteArray = pair[1]
		for k in 120:
			var cs := _free_cell(rng, w, h, solid)
			var ct := _free_cell(rng, w, h, solid)
			if cs.x < 0 or ct.x < 0 or cs == ct:
				continue
			var a := _center(cs)
			var b := _center(ct)
			var ids: Array = pf.grid.get_id_path(cs, ct)
			pf.sight_calls = 0
			var path: Array = pf.find(solid, a.x, a.y, b.x, b.y)
			if ids.is_empty():
				eq(path, [], "%s to %s: no way" % [str(cs), str(ct)])
				continue
			found += 1
			check(not path.is_empty() and path.size() <= ids.size(), "%s to %s: %d points for a raw path of %d" % [str(cs), str(ct), path.size(), ids.size()])
			check(pf.sight_calls <= (Pathfinder.LOOKAHEAD - 1) * ids.size(), "%s to %s: %d sight checks for %d points" % [str(cs), str(ct), pf.sight_calls, ids.size()])
			var at := a
			for p in path:
				if not pf.sight(solid, at, p):
					failures.append("%s to %s: no line of sight from %s to %s" % [str(cs), str(ct), str(at), str(p)])
					break
				at = p
	check(found >= 60, "enough paths were found on the real map: %d" % found)
	g.world.free()
