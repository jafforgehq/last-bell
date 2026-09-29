## Grid pathfinding on Godot's AStarGrid2D (8-way, no corner cutting), with
## string-pulling so walkers move in straight lines between turns.
extends RefCounted

var W: int
var H: int
var grid: AStarGrid2D


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


func sight(solid: PackedByteArray, a: Vector2, b: Vector2, r: float = 0.3) -> bool:
	var dv := b - a
	var dist := dv.length()
	var n := maxi(1, ceili(dist / 0.2))
	var nrm := Vector2.ZERO if dist == 0.0 else Vector2(-dv.y, dv.x) / dist * r
	for i in n + 1:
		var p := a + dv * (float(i) / float(n))
		if not free_at(solid, floori(p.x), floori(p.y)):
			return false
		if not free_at(solid, floori(p.x + nrm.x), floori(p.y + nrm.y)):
			return false
		if not free_at(solid, floori(p.x - nrm.x), floori(p.y - nrm.y)):
			return false
	return true


func smooth(solid: PackedByteArray, pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out: Array = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not sight(solid, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out
