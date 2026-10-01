## Grid pathfinding on Godot's AStarGrid2D (8-way, no corner cutting), with
## string-pulling so walkers move in straight lines between turns.
extends RefCounted

## How many path points ahead `smooth` looks for one it can walk to in a straight
## line. A path of at most LOOKAHEAD + 1 points comes out exactly as if it looked
## all the way along; on a longer one the walker gets a waypoint every so many
## cells, so what one path costs grows with its length and not with its square.
const LOOKAHEAD := 24
## How far apart, in tiles, `sight` samples a line.
const SIGHT_STEP := 0.2

var W: int
var H: int
var grid: AStarGrid2D
## How many times `sight` has been called. For tests and profiling: whoever reads
## it resets it.
var sight_calls := 0


func _init(w: int, h: int, solid: PackedByteArray) -> void:
	W = w
	H = h
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, W, H)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for i in W * H:
		if solid[i]:
			@warning_ignore("integer_division")
			grid.set_point_solid(Vector2i(i % W, i / W), true)


func set_solid(i: int, value: bool) -> void:
	@warning_ignore("integer_division")
	grid.set_point_solid(Vector2i(i % W, i / W), value)


func free_at(solid: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and solid[y * W + x] == 0


func nearest_free(solid: PackedByteArray, x: int, y: int):
	if free_at(solid, x, y):
		return Vector2i(x, y)
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if free_at(solid, x + dx, y + dy):
					return Vector2i(x + dx, y + dy)
	return null


## Returns waypoints (Vector2, tile units) ending exactly at the target, or an
## empty array when there is no way through.
func find(solid: PackedByteArray, sx: float, sy: float, tx: float, ty: float) -> Array:
	var s = nearest_free(solid, floori(sx), floori(sy))
	var t = nearest_free(solid, floori(tx), floori(ty))
	if s == null or t == null:
		return []
	if s == t:
		return [Vector2(tx, ty)]
	var ids := grid.get_id_path(s, t)
	if ids.is_empty():
		return []
	var pts: Array = [Vector2(sx, sy)]
	for c in ids:
		pts.append(Vector2(c.x + 0.5, c.y + 0.5))
	pts[pts.size() - 1] = Vector2(tx, ty)
	var out := smooth(solid, pts)
	out.remove_at(0)
	return out


## Whether a walker 2r wide fits along the line a to b: the line and the two
## lines r to either side of it are sampled every SIGHT_STEP tiles and none of
## the samples may be in a solid tile (or off the map). The cells looked at are
## the ones `free_at` would test, written out in place because this is the hot
## loop of `smooth`; a line whose whole corridor is on the map skips the bounds
## checks (the result is the same as with them).
func sight(solid: PackedByteArray, a: Vector2, b: Vector2, r: float = 0.3) -> bool:
	sight_calls += 1
	var dv := b - a
	var dist := dv.length()
	var n := maxi(1, ceili(dist / SIGHT_STEP))
	var fn := float(n)
	var nrm := Vector2.ZERO if dist == 0.0 else Vector2(-dv.y, dv.x) / dist * r
	var w := W
	var h := H
	var m := absf(r) + 0.05
	if minf(a.x, b.x) > m and minf(a.y, b.y) > m and maxf(a.x, b.x) < w - m and maxf(a.y, b.y) < h - m:
		for i in n + 1:
			var p := a + dv * (float(i) / fn)
			if solid[floori(p.y) * w + floori(p.x)] != 0 or solid[floori(p.y + nrm.y) * w + floori(p.x + nrm.x)] != 0 or solid[floori(p.y - nrm.y) * w + floori(p.x - nrm.x)] != 0:
				return false
		return true
	for i in n + 1:
		var p := a + dv * (float(i) / fn)
		var x := floori(p.x)
		var y := floori(p.y)
		if x < 0 or y < 0 or x >= w or y >= h or solid[y * w + x] != 0:
			return false
		x = floori(p.x + nrm.x)
		y = floori(p.y + nrm.y)
		if x < 0 or y < 0 or x >= w or y >= h or solid[y * w + x] != 0:
			return false
		x = floori(p.x - nrm.x)
		y = floori(p.y - nrm.y)
		if x < 0 or y < 0 or x >= w or y >= h or solid[y * w + x] != 0:
			return false
	return true


## String-pulling: from each kept point, on to the farthest of the next LOOKAHEAD
## points that can be seen from it (a path that has no line of sight to the next
## point takes it anyway: neighbouring cells always do).
func smooth(solid: PackedByteArray, pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out: Array = [pts[0]]
	var last := pts.size() - 1
	var i := 0
	while i < last:
		var j := mini(last, i + LOOKAHEAD)
		while j > i + 1 and not sight(solid, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out
