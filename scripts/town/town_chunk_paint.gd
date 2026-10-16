## The paint of one layer of one chunk of the town (scripts/town/town_world.gd makes five of them for each chunk): the pictures of the art kit that are not the ground itself.
## Drawn once, when the chunk is first seen (a chunk that is off screen costs nothing); the nodes of a layer are the layer's z index.
##
##   layer 0  ground detail   the kerb on every sidewalk cell that touches the road (cell by the sides the road is on), the lane paint (white edge lines, the yellow double line, zebra
##                            crossings on the four arms of a crossing), manholes and drains, the edge of the lawn where it meets paving, wall or fence, soft patches of other grass,
##                            the soft shadow of a wall on the floor and the ground beside it (north and west walls), fallen leaves
##   layer 1  decals          the kit objects of layer 1 (clutter, rugs, steps...) that stand outdoors
##   layer 2  low props       bins, mailboxes, bikes, benches, garden beds, hydrants outdoors
##   layer 3  wall tops       the fill of each wall cell (its material, a second look for one in six), the autotile outline over it by the open sides, the windows and their barricades
##   layer 4  tall things     the lines of fence and hedge (cell by connected sides), their gates, cars, lamps, sheds, swing sets: everything that stands
## What is inside a house is not here (scripts/town/town_house_paint.gd). With no kit (the manifest is missing) layer 0 draws the old curbs and lane dashes.
extends Node2D

const TILE := 64.0
## The generator's street grid (scripts/town/town_gen.gd): a 4 tile road at the end of every 32 tiles, after a 28 tile block.
const PITCH := 32
const BLOCK := 28
const DASH := 0.5
const G_LAWN := 0
const G_ASPHALT := 1
const G_SIDEWALK := 2
const G_WALL := 255

var world
var rect: Rect2
var layer := 0
var chunk := 0
var road_id := 0
var grass_id := 0
## False on a map whose roads are not the generator's grid (a raid site, scripts/prison/prison_site.gd: `data.road_grid`): no lane paint, zebras, manholes or drains there.
var grid := true


func setup(w, r: Rect2, lyr: int = 0, ci: int = 0) -> void:
	world = w
	grid = bool(w.d.get("road_grid", true))
	rect = r
	layer = lyr
	chunk = ci
	z_index = lyr if lyr < 5 else 4
	if w.d.terrainTypes.has("ASPHALT"):
		road_id = int(w.d.terrainTypes.ASPHALT.id)
		grass_id = int(w.d.terrainTypes.GRASS.id)


func _draw() -> void:
	if world == null:
		return
	if not world.kit:
		if layer == 0:
			_legacy()
		return
	match layer:
		0:
			_ground()
		1, 2:
			_objects(layer)
		3:
			_walls()
		4:
			_lines()
			_objects(4)
		5:
			_apron()


static func hash2(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


## One look of the kit at a tile (x, y) of the map, `dy` and `dx` tiles further (the look's own offset and size are in pixels).
func _put(look: Dictionary, x: float, y: float) -> void:
	if look.is_empty():
		return
	draw_texture_rect_region(look.tex, Rect2(Vector2(x, y) * TILE + look.off, look.size), look.src)


## A look turned: its middle at (x, y) tiles, rotated by `rot` radians.
func _put_turned(look: Dictionary, x: float, y: float, rot: float) -> void:
	if look.is_empty():
		return
	draw_set_transform(Vector2(x, y) * TILE, rot, Vector2.ONE)
	draw_texture_rect_region(look.tex, Rect2(-look.size * 0.5, look.size), look.src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------------ layer 0 --
# One pass over the chunk's tiles sorts what is to be drawn into a list for each picture (the kerb's, the paint's, the shadows'...), and the lists are then drawn one after the other:
# consecutive draws of one texture are one draw call, so a chunk costs a few calls, not one for each cell.

const KERBS := ["s", "w", "n", "e", "corner_se", "corner_sw", "corner_nw", "corner_ne"]
const LANES := ["edge_n", "edge_e", "edge_s", "edge_w", "double_h", "double_v", "cross_h", "cross_v"]

var _edge := PackedInt32Array()
var _kerb := PackedInt32Array()
var _lane := PackedInt32Array()
var _shade := PackedInt32Array()
var _misc := PackedInt32Array()
var _leaves := PackedInt32Array()


func _ground() -> void:
	var W: int = world.W
	var H: int = world.H
	var grp: PackedByteArray = world.grp
	var fence: PackedByteArray = world.fence
	var looks: Dictionary = world.looks
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := mini(W, int(rect.end.x))
	var y1 := mini(H, int(rect.end.y))
	_edge.clear()
	_kerb.clear()
	_lane.clear()
	_shade.clear()
	_misc.clear()
	_leaves.clear()
	# soft patches of other grass, first (under everything else of this layer): one candidate to each 7 x 7 tiles, a third of them kept
	var patches: Array = looks.patch
	if not patches[0].is_empty():
		for cy in range(y0 / 7 - 1, y1 / 7 + 2):
			for cx in range(x0 / 7 - 1, x1 / 7 + 2):
				var h := hash2(cx + 911, cy + 377)
				if h % 3 != 0:
					continue
				var px := cx * 7 + (h >> 4) % 7
				var py := cy * 7 + (h >> 9) % 7
				if px < x0 or py < y0 or px >= x1 or py >= y1:
					continue
				var ok := true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var qx := px + dx
						var qy := py + dy
						if qx < 0 or qy < 0 or qx >= W or qy >= H or grp[qy * W + qx] != G_LAWN or fence[qy * W + qx] != 0:
							ok = false
				if ok:
					var pl: Dictionary = patches[(h >> 14) & 3]
					draw_texture_rect_region(pl.tex, Rect2((Vector2(px, py) + Vector2(0.5, 0.5)) * TILE - pl.size * 0.5, pl.size), pl.src)
	# the tiles
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * W + x
			var g := int(grp[i])
			var up := i - W if y > 0 else -1
			var dn := i + W if y + 1 < H else -1
			var lf := i - 1 if x > 0 else -1
			var rt := i + 1 if x + 1 < W else -1
			if g == G_SIDEWALK:
				var rn: bool = up >= 0 and grp[up] == G_ASPHALT
				var rs: bool = dn >= 0 and grp[dn] == G_ASPHALT
				var rw: bool = lf >= 0 and grp[lf] == G_ASPHALT
				var re: bool = rt >= 0 and grp[rt] == G_ASPHALT
				if rs and re:
					_kerb.append_array([x, y, 4])
				elif rs and rw:
					_kerb.append_array([x, y, 5])
				elif rn and rw:
					_kerb.append_array([x, y, 6])
				elif rn and re:
					_kerb.append_array([x, y, 7])
				else:
					if rs:
						_kerb.append_array([x, y, 0])
					if rn:
						_kerb.append_array([x, y, 2])
					if re:
						_kerb.append_array([x, y, 3])
					if rw:
						_kerb.append_array([x, y, 1])
				if (hash2(x, y) & 31) == 0:
					_leaves.append_array([x, y, hash2(x + 31, y + 17)])
			elif g == G_ASPHALT:
				_road(x, y)
			elif g == G_LAWN and fence[i] == 0:
				if up >= 0 and _hard(up, grp, fence):
					_edge.append_array([x, y, 0])
				if rt >= 0 and _hard(rt, grp, fence):
					_edge.append_array([x, y, 1])
				if dn >= 0 and _hard(dn, grp, fence):
					_edge.append_array([x, y, 2])
				if lf >= 0 and _hard(lf, grp, fence):
					_edge.append_array([x, y, 3])
				if (hash2(x, y) & 63) == 0:
					_leaves.append_array([x, y, hash2(x + 31, y + 17)])
			# the soft shadow of a wall to the north and to the west falls on whatever is not a wall
			if g != G_WALL:
				var wn: bool = up >= 0 and grp[up] == G_WALL
				var ww: bool = lf >= 0 and grp[lf] == G_WALL
				if wn and ww:
					_shade.append_array([x, y, 2])
				elif wn:
					_shade.append_array([x, y, 0])
				elif ww:
					_shade.append_array([x, y, 1])
				elif up >= 0 and lf >= 0 and grp[up - 1] == G_WALL:
					_shade.append_array([x, y, 3])
	# drawn by picture
	var ledge: Array = looks.lawn_edge_list
	for k in range(0, _edge.size(), 3):
		_put(ledge[_edge[k + 2]], _edge[k], _edge[k + 1])
	var shade_l: Array = looks.shadow_list
	for k in range(0, _shade.size(), 3):
		_put(shade_l[_shade[k + 2]], _shade[k], _shade[k + 1])
	var kerb_l: Array = looks.kerb_list
	for k in range(0, _kerb.size(), 3):
		_put(kerb_l[_kerb[k + 2]], _kerb[k], _kerb[k + 1])
	var lane_l: Array = looks.lane_list
	for k in range(0, _lane.size(), 3):
		_put(lane_l[_lane[k + 2]], float(_lane[k]) * 0.5, float(_lane[k + 1]) * 0.5)
	var misc_l: Array = looks.misc_list
	for k in range(0, _misc.size(), 3):
		_put(misc_l[_misc[k + 2]], float(_misc[k]) * 0.5, float(_misc[k + 1]) * 0.5)
	var leaf_l: Array = looks.leaves
	for k in range(0, _leaves.size(), 3):
		var h: int = _leaves[k + 2]
		_put_turned(leaf_l[h % 3], float(_leaves[k]) + 0.5, float(_leaves[k + 1]) + 0.5, float((h >> 3) & 255) / 255.0 * TAU)


## Whether the lawn next to this cell has a hard edge there: paving or a wall (not another lawn, a dirt path, a fence or a hedge).
func _hard(j: int, grp: PackedByteArray, fence: PackedByteArray) -> bool:
	var g := int(grp[j])
	return g == G_ASPHALT or g == G_SIDEWALK or g == G_WALL


## The paint and the small furniture of a road cell: edge lines (0 to 3: n e s w), the yellow double line (4, 5), zebra bars (6, 7); a manhole (0, 1), a drain (2, 3 along x, 4 along y); a leaf.
## (Positions go in half tiles: a line in the middle of two cells is drawn half a tile off.)
func _road(x: int, y: int) -> void:
	var lx := x & (PITCH - 1)
	var ly := y & (PITCH - 1)
	var in_h := ly >= BLOCK
	var in_v := lx >= BLOCK
	var h := hash2(x, y)
	var W: int = world.W
	var x2 := x * 2
	var y2 := y * 2
	if not grid:
		in_h = false
		in_v = false
	if in_h and not in_v:
		var near_edge: bool = x < 5 or x > W - 6
		if ly == BLOCK:
			_lane.append_array([x2, y2, 0])
		elif ly == PITCH - 1:
			_lane.append_array([x2, y2, 2])
		elif ly == BLOCK + 1:
			_lane.append_array([x2, y2 + 1, 4])
		if not near_edge and (lx == 25 or lx == 26 or lx == 1 or lx == 2):
			_lane.append_array([x2, y2, 6])
		elif (ly == BLOCK or ly == BLOCK + 2) and h % 130 == 0:
			_misc.append_array([x2, y2 + 1, h % 2])
		elif ly == BLOCK and h % 29 == 5 and lx > 3 and lx < 25:
			_misc.append_array([x2, y2, 2 + ((h >> 5) & 1)])
		elif ly == PITCH - 1 and h % 29 == 6 and lx > 3 and lx < 25:
			_misc.append_array([x2, y2 + 1, 2 + ((h >> 5) & 1)])
	elif in_v and not in_h:
		var near_edge: bool = y < 5 or y > world.H - 6
		if lx == BLOCK:
			_lane.append_array([x2, y2, 3])
		elif lx == PITCH - 1:
			_lane.append_array([x2, y2, 1])
		elif lx == BLOCK + 1:
			_lane.append_array([x2 + 1, y2, 5])
		if not near_edge and (ly == 25 or ly == 26 or ly == 1 or ly == 2):
			_lane.append_array([x2, y2, 7])
		elif (lx == BLOCK or lx == BLOCK + 2) and h % 130 == 0:
			_misc.append_array([x2 + 1, y2, h % 2])
		elif lx == BLOCK and h % 29 == 5 and ly > 3 and ly < 25:
			_misc.append_array([x2, y2, 4])
	if (h & 127) == 3:
		_leaves.append_array([x, y, hash2(x + 31, y + 17)])


# ------------------------------------------------------------------------ layer 3 --

var _wbuf: Array = []
var _wall_cells := PackedInt32Array()


func _walls() -> void:
	var W: int = world.W
	var H: int = world.H
	var grp: PackedByteArray = world.grp
	var wallm: PackedByteArray = world.wallm
	var looks: Dictionary = world.looks
	var walls: Array = looks.wall
	var edges: Array = looks.edge
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := mini(W, int(rect.end.x))
	var y1 := mini(H, int(rect.end.y))
	if _wbuf.is_empty():
		for k in 16:
			_wbuf.append(PackedInt32Array())
	for k in 16:
		_wbuf[k].clear()
	_wall_cells.clear()
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * W + x
			if grp[i] != G_WALL:
				continue
			_wall_cells.append(i)
			var v := 1 if hash2(x, y) % 6 == 0 else 0
			_wbuf[int(wallm[i]) * 2 + v].append(i)
	# the fills, one material and look after the other (a texture at a time)
	for k in 16:
		var buf: PackedInt32Array = _wbuf[k]
		if buf.is_empty():
			continue
		var look: Dictionary = walls[k >> 1][k & 1]
		for i in buf:
			_put(look, i % W, i / W)
	for i in _wall_cells:
		var x := i % W
		var y := i / W
		var mask := 0
		if y == 0 or grp[i - W] != G_WALL:
			mask |= 1
		if x + 1 >= W or grp[i + 1] != G_WALL:
			mask |= 2
		if y + 1 >= H or grp[i + W] != G_WALL:
			mask |= 4
		if x == 0 or grp[i - 1] != G_WALL:
			mask |= 8
		_put(edges[mask], x, y)
	for w in world.chunk_wins[chunk]:
		var o := String(w.orient)
		var look: Dictionary = looks.get("window_%s_%s_%d" % [String(w.state), o, int(w.variant) & 1], {})
		_put(look, int(w.x), int(w.y))
	for w in world.chunk_wins[chunk]:
		if bool(w.get("bar", false)):
			_put(looks.get("barricade_%s_%d" % [String(w.orient), int(w.variant) & 1], {}), int(w.x), int(w.y))


# ------------------------------------------------------------------------ layer 4 --

## The lines of fence and hedge in the chunk, cell by the sides that connect (the same line on that side), and the open leaves of the gates; a kind of line at a time.
func _lines() -> void:
	var W: int = world.W
	var H: int = world.H
	var fence: PackedByteArray = world.fence
	var cells: Array = world.looks.line
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := mini(W, int(rect.end.x))
	var y1 := mini(H, int(rect.end.y))
	if _wbuf.is_empty():
		for k in 16:
			_wbuf.append(PackedInt32Array())
	var n_lines: int = mini(cells.size(), 16)
	for k in n_lines:
		_wbuf[k].clear()
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * W + x
			var f := int(fence[i])
			if f != 0 and f < n_lines:
				_wbuf[f].append(i)
	for f in range(1, n_lines):
		for i in _wbuf[f]:
			var mask := 0
			if i >= W and fence[i - W] == f:
				mask |= 1
			if (i % W) + 1 < W and fence[i + 1] == f:
				mask |= 2
			if i + W < W * H and fence[i + W] == f:
				mask |= 4
			if (i % W) > 0 and fence[i - 1] == f:
				mask |= 8
			_put(cells[f][mask], i % W, i / W)
	var kd = world.d.get("kit")
	if kd is Dictionary:
		for g in kd.get("gates", []):
			var gx := int(g.x)
			var gy := int(g.y)
			if gx < x0 or gy < y0 or gx >= x1 or gy >= y1:
				continue
			var o := String(g.orient)
			var open_look: Dictionary = world.looks.get("gate_open_" + o, {})
			var n := int(g.w)
			if o == "h":
				_put(open_look, gx, gy)
				_put(open_look, gx + n - 1, gy)
			else:
				_put(open_look, gx, gy)
				_put(open_look, gx, gy + n - 1)


# ------------------------------------------------------------------------ apron --

## The belt of trees outside the edge of the map that this chunk touches (layer 5; only the chunks on the border have it): rows of the kit's trees, further rows darker, in the order of their y.
func _apron() -> void:
	var W: int = world.W
	var H: int = world.H
	var trees: Array = world.looks.tree
	if trees.is_empty() or trees[0].is_empty():
		return
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := mini(W, int(rect.end.x))
	var y1 := mini(H, int(rect.end.y))
	var reach := float(world.APRON)
	var items: Array = []
	for side in 4:
		var horiz := side < 2
		var touches := (y0 == 0) if side == 0 else ((y1 >= H) if side == 1 else ((x0 == 0) if side == 2 else (x1 >= W)))
		if not touches:
			continue
		var u0 := float(x0) if horiz else float(y0)
		var u1 := float(x1) if horiz else float(y1)
		if not horiz:
			# the sides along y also take the corners
			if y0 == 0:
				u0 -= reach
			if y1 >= H:
				u1 += reach
		var rows := int(reach / 2.0)
		for k in rows:
			var u := u0 + float(hash2(k * 7 + side, int(u0)) % 100) / 100.0 * 1.2
			while u < u1:
				var h := hash2(int(u * 10.0) + k * 977, side * 131 + k * 17)
				var d := 0.4 + float(k) * 2.0 + float((h >> 3) % 100) / 100.0 * 1.1
				var pos := Vector2.ZERO
				match side:
					0: pos = Vector2(u, -d - 1.0)
					1: pos = Vector2(u, float(H) + d)
					2: pos = Vector2(-d - 1.0, u)
					_: pos = Vector2(float(W) + d, u)
				items.append(Vector4(pos.x, pos.y, float(h % 10 / 4), float(k)))
				u += 1.5 + float((h >> 11) % 100) / 100.0 * 0.9
	# a variant of tree at a time (a draw call for each, not for each tree), each from the north
	items.sort_custom(func(a, b): return a.y < b.y)
	for v in 3:
		var look: Dictionary = trees[v]
		for it in items:
			if int(it.z) != v:
				continue
			var shade: float = 1.0 - 0.06 * it.w
			draw_texture_rect_region(look.tex, Rect2(Vector2(it.x, it.y) * TILE + look.off, look.size), look.src, Color(shade * 0.92, shade * 0.98, shade * 0.9))


# ----------------------------------------------------------------------- objects --

## The kit objects of this chunk and layer, a picture (a texture) at a time: the things of one layer do not overlap each other enough to need the north to south order, and the draws of one
## texture in a row are one draw call.
func _objects(lyr: int) -> void:
	var objs: Array = world.d.objects
	var list: PackedInt32Array = world.chunk_objs[chunk][lyr]
	draw_grouped(self, objs, list)


## Draws the kit objects `list` (indexes into `objs`) a texture at a time.
static func draw_grouped(ci: CanvasItem, objs: Array, list: PackedInt32Array) -> void:
	if list.size() < 3:
		for k in list:
			draw_kit(ci, objs[k])
		return
	var groups := {}
	for k in list:
		var tid: int = objs[k]._look.tex.get_instance_id()
		if not groups.has(tid):
			groups[tid] = PackedInt32Array()
		groups[tid].append(k)
	for tid in groups:
		for k in groups[tid]:
			draw_kit(ci, objs[k])


## A kit object: the picture of its look laid by the anchor round its footprint (the object's middle `cx`, `cy` and its size `w`, `h`, in tiles).
static func draw_kit(ci: CanvasItem, o: Dictionary) -> void:
	var look: Dictionary = o._look
	if o.has("turn"):
		# a picture turned a quarter (a wreck lying along y): about the middle of its footprint
		ci.draw_set_transform(Vector2(float(o.cx), float(o.cy)) * TILE, float(o.turn) * PI / 2.0, Vector2.ONE)
		ci.draw_texture_rect_region(look.tex, Rect2(-look.size * 0.5, look.size), look.src)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var tl := Vector2(float(o.cx) - float(o.w) * 0.5, float(o.cy) - float(o.h) * 0.5) * TILE
	var tint := Color.WHITE
	if o.has("tint"):
		tint = o.tint
	ci.draw_texture_rect_region(look.tex, Rect2(tl + look.off, look.size), look.src, tint)


# ----------------------------------------------------------------------- legacy --

## The gutter and the curb where paving meets the road, the soil line at the edge of grass, and the dashes of the lanes (the paint of the first town, with no kit).
func _legacy() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var W: int = world.W
	var H: int = world.H
	var t_arr: PackedByteArray = world.terrain
	var curb := Color8(206, 202, 190, 230)
	var gutter := Color8(20, 18, 16, 89)
	var soil := Color8(52, 40, 26, 115)
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := mini(W, int(rect.end.x))
	var y1 := mini(H, int(rect.end.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var t := t_arr[y * W + x]
			var right := t_arr[y * W + x + 1] if x + 1 < W else t
			var down := t_arr[(y + 1) * W + x] if y + 1 < H else t
			for k in 2:
				var n := right if k == 0 else down
				if n == t:
					continue
				var vert := k == 0
				var ex := float(x + 1) if vert else float(x)
				var ey := float(y) if vert else float(y + 1)
				var t_road := t == road_id
				var n_road := n == road_id
				if t_road != n_road:
					var s := -1 if t_road else 1
					if vert:
						draw_rect(Rect2(ex - (0.1 if s > 0 else 0.0), ey, 0.1, 1.0), gutter)
						draw_rect(Rect2(ex - (0.0 if s > 0 else 0.14), ey, 0.14, 1.0), curb)
					else:
						draw_rect(Rect2(ex, ey - (0.1 if s > 0 else 0.0), 1.0, 0.1), gutter)
						draw_rect(Rect2(ex, ey - (0.0 if s > 0 else 0.14), 1.0, 0.14), curb)
				elif (t == grass_id) != (n == grass_id):
					if vert:
						draw_rect(Rect2(ex - 0.04, ey, 0.08, 1.0), soil)
					else:
						draw_rect(Rect2(ex, ey - 0.04, 1.0, 0.08), soil)
	for m in world.d.marks:
		if m.kind == "lanes":
			_lanes(m)


func _lanes(m: Dictionary) -> void:
	var horiz: bool = m.dir == "h"
	var L: float = m.w if horiz else m.h
	var wd: float = m.h if horiz else m.w
	var c0: float = (m.cx - m.w / 2.0) if horiz else (m.cy - m.h / 2.0)
	var across: float = m.cy if horiz else m.cx
	var chunk_across0 := rect.position.y if horiz else rect.position.x
	var chunk_across1 := rect.end.y if horiz else rect.end.x
	if across + wd / 2.0 < chunk_across0 or across - wd / 2.0 > chunk_across1:
		return
	var a0 := rect.position.x if horiz else rect.position.y
	var a1 := rect.end.x if horiz else rect.end.y
	draw_set_transform(Vector2(m.cx, m.cy) * TILE, 0.0 if horiz else PI / 2.0, Vector2(TILE, TILE))
	var first := int(floor((a0 - c0) / DASH))
	var last := int(ceil((a1 - c0) / DASH))
	for k in range(maxi(0, first), mini(int(L / DASH), last)):
		var ta := c0 + float(k) * DASH
		var gap := false
		for g in m.gaps:
			if ta >= g[0] and ta < g[1]:
				gap = true
				break
		if gap:
			continue
		var t := -L / 2.0 + float(k) * DASH
		var wear := 0.5 + float((k * 2654435761 + int(m.seed) * 40503) & 1023) / 1023.0 * 0.4
		var yellow := Color8(214, 170, 58)
		yellow.a = wear
		draw_rect(Rect2(t, -0.14, DASH, 0.08), yellow)
		draw_rect(Rect2(t, 0.06, DASH, 0.08), yellow)
		var white := Color8(226, 222, 208)
		white.a = wear * 0.6
		draw_rect(Rect2(t, -wd / 2.0 + 0.35, DASH, 0.06), white)
		draw_rect(Rect2(t, wd / 2.0 - 0.41, DASH, 0.06), white)
