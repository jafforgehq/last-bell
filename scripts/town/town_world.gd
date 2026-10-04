## The ground and the things of the town (feature/town-core): a World (scripts/world.gd: the walking grids the rules read, the layers of pictures) built
## for a 192 x 192 map, a few milliseconds a frame instead of one long stall:
##
##   `begin_build(data)` then `step_build(budget_ms)` until it says true (a loading card between), or `build(data)` for all of it at once.
##
## What it does that World.build does not: the arrays are copied with the packed constructors (not a GDScript loop over 37k tiles three times);
## the ground is the same one mesh for each terrain (about a dozen draws: the greedy rectangles of World._build_ground, stepped a few rows at a time); the curbs and
## the lane paint are drawn by chunk (CHUNK x CHUNK tiles, scripts/town/town_chunk_paint.gd: a chunk off screen is not visible and so is not drawn, and
## its first draw is deferred until it is seen) instead of one `_draw` over the whole map with every dash of every road (World's GroundDetails: ~18,000 rects
## in a 192 tile town); the pictures of the objects go in the four z layers of World in batches.
## Roofs are not here (scripts/town/town_roofs.gd).
extends "res://scripts/world.gd"

const TownChunkPaint := preload("res://scripts/town/town_chunk_paint.gd")

const CHUNK := 32
const SPRITES_PER_STEP := 200
const ROWS_PER_STEP := 24

var _phase := 0
var _row := 0
var _taken := PackedByteArray()
var _pieces := {}
var _types := {}
var _obj_i := 0
var _chunks_made := 0
var _ground_node: Node2D
## The time each phase took (milliseconds), for the report and the overlay.
var build_ms := {}
## The chunks of paint, by chunk index (cy * chunks_x + cx): {"node": DrawNode, "rect": Rect2 in tiles}.
var chunks: Array = []
var chunks_x := 0
var chunks_y := 0


func begin_build(data: Dictionary) -> void:
	d = data
	W = int(d.W)
	H = int(d.H)
	_phase = 0
	_row = 0
	_obj_i = 0
	build_ms.clear()


## The whole build in one call.
func build(data: Dictionary) -> void:
	begin_build(data)
	while not step_build(1.0e9):
		pass


func build_progress() -> float:
	var total := 6.0
	var done := float(_phase)
	if _phase == 2:
		done += float(_row) / float(maxi(1, H))
	elif _phase == 5:
		done += float(_obj_i) / float(maxi(1, d.objects.size()))
	return clampf(done / total, 0.0, 1.0)


func _tick(name: String, t_in: int) -> void:
	build_ms[name] = float(build_ms.get(name, 0.0)) + float(Time.get_ticks_usec() - t_in) / 1000.0


## About `budget_ms` of the work (at least one piece); true when the world is built.
func step_build(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while _phase < 6:
		match _phase:
			0:
				_copy_arrays()
				_phase = 1
			1:
				var t1 := Time.get_ticks_usec()
				texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				_apply_deck_barriers()
				_ground_node = Node2D.new()
				_ground_node.name = "Ground"
				add_child(_ground_node)
				for type_name in d.terrainTypes:
					var info: Dictionary = d.terrainTypes[type_name]
					_types[int(info.id)] = info
				_taken.resize(W * H)
				_taken.fill(0)
				_tick("barriers", t1)
				_phase = 2
			2:
				_mesh_rows(t0, budget_ms)
				if _row >= H:
					_phase = 3
			3:
				_make_meshes()
				_phase = 4
			4:
				_make_chunks()
				_phase = 5
			5:
				_add_objects(t0, budget_ms)
				if _obj_i >= d.objects.size():
					_finish_layers()
					_phase = 6
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return _phase >= 6


func _copy_arrays() -> void:
	var t1 := Time.get_ticks_usec()
	terrain = PackedByteArray(d.terrain)
	solid_z = PackedByteArray(d.solidZ)
	solid_p = PackedByteArray(d.solidP)
	_tick("arrays", t1)


## The greedy rectangles of World._build_ground, a few rows at a time.
func _mesh_rows(t0: int, budget_ms: float) -> void:
	var t1 := Time.get_ticks_usec()
	var stop := mini(H, _row + ROWS_PER_STEP)
	while _row < stop:
		var y := _row
		var x := 0
		while x < W:
			var i := y * W + x
			var t := terrain[i]
			if t <= 0 or _taken[i] != 0 or not _types.has(int(t)):
				x += 1
				continue
			var x1 := x
			while x1 + 1 < W and terrain[i + (x1 + 1 - x)] == t and _taken[i + (x1 + 1 - x)] == 0:
				x1 += 1
			var y1 := y
			while y1 + 1 < H:
				var row := (y1 + 1) * W
				var fits := true
				for xx in range(x, x1 + 1):
					if terrain[row + xx] != t or _taken[row + xx] != 0:
						fits = false
						break
				if not fits:
					break
				y1 += 1
			for yy in range(y, y1 + 1):
				var row := yy * W
				for xx in range(x, x1 + 1):
					_taken[row + xx] = 1
			if not _pieces.has(t):
				_pieces[t] = PackedInt32Array()
			_pieces[t].append_array(PackedInt32Array([x, y, x1 + 1, y1 + 1]))
			x = x1 + 1
		_row += 1
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	_tick("ground_rects", t1)


func _make_meshes() -> void:
	var t1 := Time.get_ticks_usec()
	for t in _pieces:
		var tex: Texture2D = GD.tex(String(_types[t].file))
		var piece_uv := Vector2(128.0 / float(tex.get_width()), 128.0 / float(tex.get_height()))
		var rects: PackedInt32Array = _pieces[t]
		var quads := rects.size() / 4
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		verts.resize(quads * 4)
		uvs.resize(quads * 4)
		idx.resize(quads * 6)
		for q in quads:
			var k := q * 4
			var a := Vector2(rects[k], rects[k + 1])
			var b := Vector2(rects[k + 2], rects[k + 3])
			var base := q * 4
			verts[base] = a * TILE
			verts[base + 1] = Vector2(b.x, a.y) * TILE
			verts[base + 2] = b * TILE
			verts[base + 3] = Vector2(a.x, b.y) * TILE
			uvs[base] = a * piece_uv
			uvs[base + 1] = Vector2(b.x, a.y) * piece_uv
			uvs[base + 2] = b * piece_uv
			uvs[base + 3] = Vector2(a.x, b.y) * piece_uv
			var j := q * 6
			idx[j] = base
			idx[j + 1] = base + 1
			idx[j + 2] = base + 2
			idx[j + 3] = base
			idx[j + 4] = base + 2
			idx[j + 5] = base + 3
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance2D.new()
		mi.name = "Terrain%d" % int(t)
		mi.mesh = mesh
		mi.texture = tex
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_ground_node.add_child(mi)
	_tick("ground_meshes", t1)


## The paint of the curbs and the lanes, a node for each CHUNK x CHUNK tiles (not visible until `show_chunks` says the camera sees it).
func _make_chunks() -> void:
	var t1 := Time.get_ticks_usec()
	chunks_x = ceili(float(W) / float(CHUNK))
	chunks_y = ceili(float(H) / float(CHUNK))
	var holder := Node2D.new()
	holder.name = "Paint"
	add_child(holder)
	for cy in chunks_y:
		for cx in chunks_x:
			var rect := Rect2(float(cx * CHUNK), float(cy * CHUNK), float(CHUNK), float(CHUNK))
			var n = TownChunkPaint.new()
			n.name = "Chunk%d_%d" % [cx, cy]
			n.setup(self, rect)
			n.visible = false
			holder.add_child(n)
			chunks.append({"node": n, "rect": rect})
	_tick("chunks", t1)


## Shows the paint of the chunks that touch `view` (a Rect2 in tiles), hides the rest.
func show_chunks(view: Rect2) -> int:
	var shown := 0
	for c in chunks:
		var seen: bool = view.intersects(c.rect)
		if c.node.visible != seen:
			c.node.visible = seen
		if seen:
			shown += 1
	return shown


func _add_objects(t0: int, budget_ms: float) -> void:
	var t1 := Time.get_ticks_usec()
	if layers.is_empty():
		for spec in [["Marks", 1], ["Low", 2], ["Walls", 3], ["Big", 4]]:
			var n := Node2D.new()
			n.name = spec[0]
			n.z_index = spec[1]
			add_child(n)
			layers[spec[1]] = n
	var stop := mini(d.objects.size(), _obj_i + SPRITES_PER_STEP)
	while _obj_i < stop:
		var o: Dictionary = d.objects[_obj_i]
		var layer := int(o.layer)
		var parent: Node2D = layers.get(layer if layer != 5 else 4)
		_add_pieces(parent, o.pieces)
		_obj_i += 1
	_tick("sprites", t1)


func _finish_layers() -> void:
	_add_pieces(layers[3], d.walls)
