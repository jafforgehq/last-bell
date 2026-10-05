## The ground and the things of the town (feature/town-core, One House art pass): a World (scripts/world.gd: the walking grids the rules read, the layers of pictures) built
## for a 192 x 192 map, a few milliseconds a frame instead of one long stall:
##
##   `begin_build(data)` then `step_build(budget_ms)` until it says true (a loading card between), or `build(data)` for all of it at once.
##
## EVERYTHING IS DRAWN FROM THE ART KIT (assets/data/town_art.json through scripts/town/town_art.gd; the generator's `data.kit` says which look each tile has):
##   the ground     one mesh for each kit ground atlas and variant (about twenty draws): the greedy rectangles of World._build_ground, but a lawn, a road, a sidewalk and a floor
##                  take one of their variants by a hash of the 4 x 4 block they are in (so the 4 tile repeat of an atlas is not seen); a room's floor is its type's (`kit.ground`)
##   the paint      by chunk (CHUNK x CHUNK tiles, scripts/town/town_chunk_paint.gd; a chunk off screen is not visible and so is not drawn, and its first draw waits until it is
##                  seen): the kerb, the lane paint, the crosswalks, the edge of the lawn, soft patches, the wall shadows, leaves, manholes and drains (layer 0); the decals (1); the
##                  low props (2); the wall tops with their outlines and the windows (3); the fences, hedges, cars and everything tall (4)
##   the houses     what is inside a house (its furniture, rugs, clutter) is one node for each house (scripts/town/town_house_paint.gd), shown only while the camera is within
##                  INTERIOR_NEAR tiles of it (a roof hides it anyway): the draw calls of a view are not spent under roofs
##   the objects    `data.objects` with a `kit` field (the generator's: item, facing, state, variant) are bucketed by chunk or house and drawn by those nodes, not one Sprite2D each
##                  (an object with no `kit` is the old picture and a Sprite2D as before)
## `_process` finds the camera's rectangle itself (the town's run never called `show_chunks`) and shows the chunks and the houses it needs, a few times a second.
## Roofs are not here (scripts/render/house_view.gd). Perimeter pieces that get built are scripts/render/perimeter_view.gd's.
extends "res://scripts/world.gd"

const TownArt := preload("res://scripts/town/town_art.gd")
const TownChunkPaint := preload("res://scripts/town/town_chunk_paint.gd")
const TownHousePaint := preload("res://scripts/town/town_house_paint.gd")

const CHUNK := 32
const ROWS_PER_STEP := 24
## The phases of the build (arrays, setup, keys, ground rectangles, ground meshes, looks, chunks, objects).
const PHASES := 8
## The paint layers of a chunk (the z index of each node): ground detail, decals, low props, wall tops, tall things.
const LAYERS := [0, 1, 2, 3, 4]
## A house keeps its interior drawn while the middle of the camera is this near its walls (tiles; the roof hides it anyway, and the avatar is at the middle of the camera).
const INTERIOR_NEAR := 7.0
## Under this many pixels to the tile the small things (decals, low props, wall tops: the roofs are over them) are not shown.
const DETAIL_ZOOM := 11.0
const SHOW_EVERY := 0.12
## Ground variants: for each ground group, which variant a block takes by the low three bits of its hash (the first is the plain one).
const VARIANT_PICK := {
	"lawn": [0, 0, 0, 0, 1, 1, 2, 2], "asphalt": [0, 0, 0, 0, 0, 1, 2, 2], "sidewalk": [0, 0, 0, 0, 0, 1, 1, 2], "dirt_path": [0, 0, 0, 0, 1, 1, 1, 1],
	"gravel": [0, 0, 0, 0, 1, 1, 1, 1], "floor_wood": [0, 0, 0, 1, 1, 1, 0, 1], "floor_hall": [0, 0, 0, 0, 0, 0, 0, 0], "floor_kitchen": [0, 0, 0, 1, 0, 0, 1, 0],
	"floor_carpet": [0, 0, 1, 0, 1, 0, 0, 1], "floor_bath": [0, 0, 1, 0, 0, 1, 0, 0], "floor_runner_h": [0, 0, 0, 0, 0, 0, 0, 0], "floor_runner_v": [0, 0, 0, 0, 0, 0, 0, 0],
}
## The group of terrain by its name (an index into TownArt.GROUNDS), when the generator's `kit.ground` says nothing. A wall stands on the hall's floor, a fence on the lawn.
const BASE_GROUP := {
	"GRASS": "lawn", "ASPHALT": "asphalt", "SIDEWALK": "sidewalk", "YARD": "dirt_path", "SOIL": "dirt_path", "DIRT": "dirt_path", "CONCRETE": "sidewalk",
	"LINO": "floor_kitchen", "TERRAZZO": "floor_hall", "WOOD": "floor_wood", "KITCHEN": "floor_kitchen", "ROOF": "floor_hall", "ROOF_LIGHT": "floor_hall",
	"WALL_METAL": "lawn", "DOOR_WOOD": "floor_wood", "WALL_BRICK": "floor_hall", "WALL_PLASTER": "floor_hall",
}
const G_WALL := 255
## How far past the edge of the map the dark lawn and the belt of trees reach (tiles): the camera may be at the edge and half a screen wide.
const APRON := 14

var _phase := 0
var _row := 0
var _taken := PackedByteArray()
var _pieces := {}
var _types := {}
var _obj_i := 0
var _mesh_keys: Array = []
var _mesh_i := 0
var _chunks_made := 0
var _ground_node: Node2D
var _legacy_tex := {}
## The time each phase took (milliseconds), for the report and the overlay.
var build_ms := {}
## The chunks of paint, by chunk index (cy * chunks_x + cx): {"node": the chunk's holder, "rect": Rect2 in tiles}.
var chunks: Array = []
var chunks_x := 0
var chunks_y := 0

## Whether the ground is the kit's (false: the old terrain pictures, when the manifest is missing).
var kit := false
## Per tile: the ground group (an index into TownArt.GROUNDS, G_WALL for a wall top), the wall material code, the line of fence or hedge code (the tables of TownArt).
var grp := PackedByteArray()
var wallm := PackedByteArray()
var fence := PackedByteArray()
## The terrain ids by name.
var t_wall_brick := 20
var t_wall_plaster := 21
var t_wall_metal := 22
var t_door := 23
## The looks the painters draw with: built once (`_make_looks`).
var looks := {}
## The objects of the kit by chunk: for each chunk five lists (by layer 0..4) of indexes into `d.objects`; and the windows by chunk.
var chunk_objs: Array = []
var chunk_wins: Array = []
## The objects inside a house: house id to a PackedInt32Array of indexes into `d.objects`, and the nodes that draw them.
var house_objs := {}
var house_nodes := {}
var house_rects := {}

var _keys := PackedInt32Array()
var _kg := PackedByteArray()
var _kw := PackedByteArray()
var _kl := PackedByteArray()
var _bh := PackedByteArray()
var _bw := 0
var _base_group := PackedInt32Array()
var _var := PackedByteArray()
var _holder: Node2D
var _houses_holder: Node2D
var _t_show := 1.0
var _last_view := Rect2()
var _last_zoom := -1.0
var _last_centre := Vector2(-1.0e9, -1.0e9)
var _detail_on := true


func begin_build(data: Dictionary) -> void:
	d = data
	W = int(d.W)
	H = int(d.H)
	_phase = 0
	_row = 0
	_obj_i = 0
	_mesh_keys = []
	_mesh_i = 0
	build_ms.clear()
	kit = TownArt.has_item("lawn") and TownArt.has_item("asphalt") and TownArt.has_item("sidewalk") and not TownArt.ground("lawn").is_empty()


## The whole build in one call.
func build(data: Dictionary) -> void:
	begin_build(data)
	while not step_build(1.0e9):
		pass


func build_progress() -> float:
	var total := float(PHASES)
	var done := float(_phase)
	if _phase == 2 or _phase == 3:
		done += float(_row) / float(maxi(1, H))
	elif _phase == 4:
		done += float(_mesh_i) / float(maxi(1, _mesh_keys.size()))
	elif _phase == 7:
		done += float(_obj_i) / float(maxi(1, d.objects.size()))
	return clampf(done / total, 0.0, 1.0)


func _tick(name: String, t_in: int) -> void:
	build_ms[name] = float(build_ms.get(name, 0.0)) + float(Time.get_ticks_usec() - t_in) / 1000.0


## About `budget_ms` of the work (at least one piece); true when the world is built.
func step_build(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while _phase < PHASES:
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
				_setup_tables()
				_tick("barriers", t1)
				_phase = 2
			2:
				_key_rows(t0, budget_ms)
				if _row >= H:
					_row = 0
					_taken.resize(W * H)
					_taken.fill(0)
					_phase = 3
			3:
				_mesh_rows(t0, budget_ms)
				if _row >= H:
					_phase = 4
			4:
				# (one ground picture's mesh at a time: each loads its picture, the longest single piece of the build)
				if _mesh_keys.is_empty():
					_mesh_keys = _pieces.keys()
				_make_meshes(t0, budget_ms)
				if _mesh_i >= _mesh_keys.size():
					if kit:
						_make_apron_ground()
					_pieces.clear()
					_keys = PackedInt32Array()
					_phase = 5
			5:
				# (the looks of the paint: about forty kit pictures are loaded here)
				var t2 := Time.get_ticks_usec()
				if kit:
					_make_looks()
				_tick("looks", t2)
				_phase = 6
			6:
				_make_chunks()
				_phase = 7
			7:
				_add_objects(t0, budget_ms)
				if _obj_i >= d.objects.size():
					_finish_layers()
					_phase = 8
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return _phase >= PHASES


func _copy_arrays() -> void:
	var t1 := Time.get_ticks_usec()
	terrain = PackedByteArray(d.terrain)
	solid_z = PackedByteArray(d.solidZ)
	solid_p = PackedByteArray(d.solidP)
	# (the tiles under low props: a shot goes over them; a town's data without the key shoots as it did)
	var low = d.get("shot_low")
	shot_low = low if low is PackedByteArray and (low as PackedByteArray).size() == W * H else PackedByteArray()
	_tick("arrays", t1)


## The tables of the ground: terrain id to group, the variant picks, the hash of each 4 x 4 block, and the generator's per tile codes (`data.kit`).
func _setup_tables() -> void:
	_base_group.resize(256)
	_base_group.fill(-1)
	for name in d.terrainTypes:
		var id := int(d.terrainTypes[name].id)
		if id >= 0 and id < 256 and BASE_GROUP.has(name):
			_base_group[id] = TownArt.GROUNDS.find(String(BASE_GROUP[name]))
		match String(name):
			"WALL_BRICK": t_wall_brick = id
			"WALL_PLASTER": t_wall_plaster = id
			"WALL_METAL": t_wall_metal = id
			"DOOR_WOOD": t_door = id
	_var.resize(TownArt.GROUNDS.size() * 8)
	for g in TownArt.GROUNDS.size():
		var pick: Array = VARIANT_PICK.get(TownArt.GROUNDS[g], [0, 0, 0, 0, 0, 0, 0, 0])
		for k in 8:
			_var[g * 8 + k] = int(pick[k])
	_bw = (W + 3) >> 2
	var bh := (H + 3) >> 2
	_bh.resize(_bw * bh)
	for by in bh:
		for bx in _bw:
			var h := (bx * 374761393 + by * 668265263) & 0x7fffffff
			h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
			_bh[by * _bw + bx] = (h ^ (h >> 16)) & 255
	var k_d = d.get("kit")
	var n := W * H
	_kg = PackedByteArray()
	_kw = PackedByteArray()
	_kl = PackedByteArray()
	if k_d is Dictionary:
		if k_d.get("ground") is PackedByteArray and (k_d.ground as PackedByteArray).size() == n:
			_kg = k_d.ground
		if k_d.get("wall") is PackedByteArray and (k_d.wall as PackedByteArray).size() == n:
			_kw = k_d.wall
		if k_d.get("line") is PackedByteArray and (k_d.line as PackedByteArray).size() == n:
			_kl = k_d.line
	_keys.resize(n)
	_keys.fill(-1)
	grp.resize(n)
	grp.fill(0)
	wallm.resize(n)
	wallm.fill(0)
	fence.resize(n)
	fence.fill(0)


## The key of each tile (the picture its ground is: a group and a variant), a few rows at a time. With the kit the variant is by the block's hash; without it the key is the terrain id.
func _key_rows(t0: int, budget_ms: float) -> void:
	var t1 := Time.get_ticks_usec()
	var stop := mini(H, _row + ROWS_PER_STEP * 2)
	var has_kg := _kg.size() == W * H
	var has_kw := _kw.size() == W * H
	var has_kl := _kl.size() == W * H
	var hall := TownArt.GROUNDS.find("floor_hall")
	while _row < stop:
		var y := _row
		var base := y * W
		var brow := (y >> 2) * _bw
		for x in W:
			var i := base + x
			var t := terrain[i]
			if not kit:
				_keys[i] = t if (t > 0 and _types.has(int(t))) else -1
				continue
			var code := int(_kg[i]) if has_kg else 0
			var g := (code - 1) if code > 0 else int(_base_group[t])
			var wall := t == t_wall_brick or t == t_wall_plaster
			if wall:
				g = hall
				grp[i] = G_WALL
				var wm := int(_kw[i]) if has_kw else 0
				wallm[i] = wm if wm > 0 else (1 if t == t_wall_brick else 7)
			elif g >= 0:
				grp[i] = g
			if t == t_wall_metal:
				fence[i] = 3
			if has_kl and _kl[i] != 0:
				fence[i] = _kl[i]
			if g < 0:
				continue
			_keys[i] = g * 4 + int(_var[g * 8 + (int(_bh[brow + (x >> 2)]) & 7)])
		_row += 1
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	_tick("keys", t1)


## The greedy rectangles of World._build_ground over the keys, a few rows at a time.
func _mesh_rows(t0: int, budget_ms: float) -> void:
	var t1 := Time.get_ticks_usec()
	var stop := mini(H, _row + ROWS_PER_STEP)
	while _row < stop:
		var y := _row
		var x := 0
		while x < W:
			var i := y * W + x
			var t := _keys[i]
			if t < 0 or _taken[i] != 0:
				x += 1
				continue
			var x1 := x
			while x1 + 1 < W and _keys[i + (x1 + 1 - x)] == t and _taken[i + (x1 + 1 - x)] == 0:
				x1 += 1
			var y1 := y
			while y1 + 1 < H:
				var row := (y1 + 1) * W
				var fits := true
				for xx in range(x, x1 + 1):
					if _keys[row + xx] != t or _taken[row + xx] != 0:
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


## The picture of a ground key: the kit's atlas of its group and variant, or (no kit) the terrain's own.
func _texture_of(key: int) -> Texture2D:
	if kit:
		var atlases: Array = TownArt.ground(String(TownArt.GROUNDS[key >> 2]))
		if atlases.is_empty():
			return null
		return atlases[mini(key & 3, atlases.size() - 1)]
	return GD.tex(String(_types[key].file))


## The meshes of the ground, one picture's at a time until `budget_ms` is spent (each loads its picture: the longest single piece of the build).
func _make_meshes(t0: int, budget_ms: float) -> void:
	var t1 := Time.get_ticks_usec()
	# a quad reaches this far (world pixels) past its tile edges, so that no hairline shows between two pictures at a fractional zoom
	var eps := 0.3 if kit else 0.0
	while _mesh_i < _mesh_keys.size():
		var t = _mesh_keys[_mesh_i]
		_mesh_i += 1
		var tex := _texture_of(int(t))
		if tex == null:
			continue
		var piece_uv := Vector2(0.25, 0.25) if kit else Vector2(128.0 / float(tex.get_width()), 128.0 / float(tex.get_height()))
		var rects: PackedInt32Array = _pieces[t]
		var quads := rects.size() / 4
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		verts.resize(quads * 4)
		uvs.resize(quads * 4)
		idx.resize(quads * 6)
		var ep := Vector2(eps, eps)
		var euv := ep / TILE * piece_uv
		for q in quads:
			var k := q * 4
			var a := Vector2(rects[k], rects[k + 1])
			var b := Vector2(rects[k + 2], rects[k + 3])
			var base := q * 4
			var pa := a * TILE - ep
			var pb := b * TILE + ep
			var ua := a * piece_uv - euv
			var ub := b * piece_uv + euv
			verts[base] = pa
			verts[base + 1] = Vector2(pb.x, pa.y)
			verts[base + 2] = pb
			verts[base + 3] = Vector2(pa.x, pb.y)
			uvs[base] = ua
			uvs[base + 1] = Vector2(ub.x, ua.y)
			uvs[base + 2] = ub
			uvs[base + 3] = Vector2(ua.x, ub.y)
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
		mi.name = "Ground%d" % int(t)
		mi.mesh = mesh
		mi.texture = tex
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_ground_node.add_child(mi)
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	_tick("ground_meshes", t1)


## Outside the map, a darker lawn all round (the belt of trees on it is the border chunks' own paint, layer 5).
func _make_apron_ground() -> void:
	var atlases: Array = TownArt.ground("lawn")
	if atlases.is_empty():
		return
	var m := float(APRON + 6)
	var a := Vector2(-m, -m) * TILE
	var b := Vector2(float(W) + m, float(H) + m) * TILE
	var piece_uv := Vector2(0.25, 0.25) / TILE
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([a * piece_uv, Vector2(b.x, a.y) * piece_uv, b * piece_uv, Vector2(a.x, b.y) * piece_uv])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.name = "Apron"
	mi.mesh = mesh
	mi.texture = atlases[0]
	mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	mi.modulate = Color(0.58, 0.68, 0.54)
	_ground_node.add_child(mi)
	_ground_node.move_child(mi, 0)


## The looks the painters use, found once.
func _make_looks() -> void:
	var edge: Array = []
	for m in 16:
		edge.append(TownArt.cell("wall_edges", str(m)))
	var wall: Array = []
	for m in TownArt.WALL_MATS.size():
		var pair: Array = []
		for v in 2:
			pair.append(TownArt.look(String(TownArt.WALL_MATS[m]), "", "", v) if m > 0 else {})
		wall.append(pair)
	var line_cells: Array = []
	for c in TownArt.LINES.size():
		var cells: Array = []
		for m in 16:
			cells.append(TownArt.cell(String(TownArt.LINES[c]), str(m)) if c > 0 else {})
		line_cells.append(cells)
	looks = {
		"edge": edge, "wall": wall, "line": line_cells,
		"kerb": {}, "lane": {}, "shadow": {}, "lawn_edge": {}, "patch": [], "leaves": [], "manhole": [], "drain_h": [], "drain_v": [],
	}
	for key in ["s", "w", "n", "e", "corner_se", "corner_sw", "corner_nw", "corner_ne", "inner_se", "inner_sw", "inner_nw", "inner_ne"]:
		looks.kerb[key] = TownArt.cell("kerb", key)
	for key in ["dash_h", "dash_v", "double_h", "double_v", "edge_n", "edge_e", "edge_s", "edge_w", "cross_h", "cross_v", "stop_h", "stop_v"]:
		looks.lane[key] = TownArt.cell("lane_markings", key)
	for key in ["n", "w", "nw", "diag_nw"]:
		looks.shadow[key] = TownArt.cell("wall_shadows", key)
	for key in ["n", "e", "s", "w"]:
		looks.lawn_edge[key] = TownArt.cell("lawn_edge", key)
	# the lists the ground painter draws by (indexes in the order of its constants)
	looks["kerb_list"] = TownChunkPaint.KERBS.map(func(k): return looks.kerb[k])
	looks["lane_list"] = TownChunkPaint.LANES.map(func(k): return looks.lane[k])
	looks["shadow_list"] = ["n", "w", "nw", "diag_nw"].map(func(k): return looks.shadow[k])
	looks["lawn_edge_list"] = ["n", "e", "s", "w"].map(func(k): return looks.lawn_edge[k])
	for v in 4:
		looks.patch.append(TownArt.look("lawn_patch", "", "", v))
	for v in 3:
		looks.leaves.append(TownArt.look("leaves", "", "", v))
	for v in 2:
		looks.manhole.append(TownArt.look("manhole", "", "", v))
		looks.drain_h.append(TownArt.look("drain", "h", "", v))
	looks.drain_v.append(TownArt.look("drain", "v", "", 0))
	looks["tree"] = [TownArt.look("tree", "", "", 0), TownArt.look("tree", "", "", 1), TownArt.look("tree", "", "", 2)]
	looks["misc_list"] = [looks.manhole[0], looks.manhole[1], looks.drain_h[0], looks.drain_h[1], looks.drain_v[0]]
	for state in ["intact", "broken", "boarded"]:
		for o in ["h", "v"]:
			for v in 2:
				looks["window_%s_%s_%d" % [state, o, v]] = TownArt.look("window", o, state, v)
	for o in ["h", "v"]:
		for v in 2:
			looks["barricade_%s_%d" % [o, v]] = TownArt.look("barricade_window", o, "", v)
	for o in ["h", "v"]:
		looks["gate_open_" + o] = TownArt.look("gate_picket", o, "open", 0)
		looks["gate_closed_" + o] = TownArt.look("gate_picket", o, "closed", 0)


## The paint of the chunks (a holder node for each, its layer nodes inside: not visible until `show_chunks` says the camera sees it) and the lists the painters read.
func _make_chunks() -> void:
	var t1 := Time.get_ticks_usec()
	chunks_x = ceili(float(W) / float(CHUNK))
	chunks_y = ceili(float(H) / float(CHUNK))
	_holder = Node2D.new()
	_holder.name = "Paint"
	add_child(_holder)
	_houses_holder = Node2D.new()
	_houses_holder.name = "Interiors"
	add_child(_houses_holder)
	for cy in chunks_y:
		for cx in chunks_x:
			var rect := Rect2(float(cx * CHUNK), float(cy * CHUNK), float(CHUNK), float(CHUNK))
			var holder := Node2D.new()
			holder.name = "Chunk%d_%d" % [cx, cy]
			holder.visible = false
			_holder.add_child(holder)
			var lists: Array = []
			for layer in LAYERS:
				if not kit and layer != 0:
					break
				var n = TownChunkPaint.new()
				n.name = "Layer%d" % layer
				n.setup(self, rect, layer, cy * chunks_x + cx)
				holder.add_child(n)
				lists.append(PackedInt32Array())
			if kit and (cx == 0 or cy == 0 or cx == chunks_x - 1 or cy == chunks_y - 1):
				var ap = TownChunkPaint.new()
				ap.name = "Apron"
				ap.setup(self, rect, 5, cy * chunks_x + cx)
				holder.add_child(ap)
			chunk_objs.append(lists)
			chunk_wins.append([])
			chunks.append({"node": holder, "rect": rect})
	_tick("chunks", t1)


## The chunks that touch `view` (a Rect2 in tiles) are shown, the rest hidden. Returns how many are shown. A chunk that comes into view has its layers shown a few at a time over the next
## ticks (a layer draws all of its chunk when it is first shown: five at once would be one long frame), except at the start (`immediate`), when the loading card is still up.
func show_chunks(view: Rect2, immediate: bool = true) -> int:
	var shown := 0
	for c in chunks:
		var seen: bool = view.intersects(c.rect)
		if c.node.visible != seen:
			c.node.visible = seen
			if seen and not immediate:
				var first := true
				for n in c.node.get_children():
					if first:
						first = false
						continue
					if not n.visible:
						continue
					n.visible = false
					_pending.append(n)
		if seen:
			shown += 1
	return shown


## A layer or two of the chunks that came into view are shown (`_pending`).
func _stage_layers() -> void:
	for k in 2:
		if _pending.is_empty():
			return
		var n: Node2D = _pending.pop_front()
		if is_instance_valid(n):
			var z := int(n.layer)
			n.visible = _detail_on or z == 0 or z >= 4


## The camera's rectangle in tiles and its zoom (pixels to the tile), from the canvas transform: the town's run does not tell the world where the camera is.
func _view_of_camera() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var to_screen := get_global_transform_with_canvas()
	var inv := to_screen.affine_inverse()
	var screen := Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	_last_zoom = to_screen.get_scale().x * TILE
	return Rect2((inv * screen).position / TILE, (inv * screen).size / TILE)


func _process(delta: float) -> void:
	_t_show += delta
	if _t_show < SHOW_EVERY or chunks.is_empty():
		return
	_t_show = 0.0
	_stage_layers()
	var view := _view_of_camera()
	if view.size.x <= 0.0:
		return
	var centre := view.get_center()
	if view == _last_view:
		return
	_last_view = view
	show_chunks(view.grow(3.0), not _shown_once)
	_shown_once = true
	# the small things are only drawn when they can be seen (under a roof, from far, they cannot)
	var detail := _last_zoom >= DETAIL_ZOOM
	if detail != _detail_on:
		_detail_on = detail
		for c in chunks:
			_set_detail(c.node)
		_last_centre = Vector2(-1.0e9, -1.0e9)
	if centre.distance_squared_to(_last_centre) > 4.0:
		_last_centre = centre
		_show_interiors(centre)


var _pending: Array = []
var _shown_once := false


func _set_detail(holder: Node2D) -> void:
	for n in holder.get_children():
		var z := int(n.layer)
		if z == 1 or z == 2 or z == 3:
			n.visible = _detail_on


## The houses near `centre` (tiles) show their furniture, the others do not.
func _show_interiors(centre: Vector2) -> void:
	var near2 := INTERIOR_NEAR * INTERIOR_NEAR
	for h in house_nodes:
		var n: Node2D = house_nodes[h]
		var hr: Rect2 = house_rects[h]
		var near_pt := Vector2(clampf(centre.x, hr.position.x, hr.end.x), clampf(centre.y, hr.position.y, hr.end.y))
		var on: bool = near_pt.distance_squared_to(centre) <= near2 and _detail_on
		if n.visible != on:
			n.visible = on


## The kit objects go to the chunk or the house they stand in; an old picture (no `kit`) is a Sprite2D, as before.
func _add_objects(t0: int, budget_ms: float) -> void:
	var t1 := Time.get_ticks_usec()
	if layers.is_empty():
		for spec in [["Marks", 1], ["Low", 2], ["Walls", 3], ["Big", 4]]:
			var n := Node2D.new()
			n.name = spec[0]
			n.z_index = spec[1]
			add_child(n)
			layers[spec[1]] = n
	var objs: Array = d.objects
	var n_objs := objs.size()
	# (until the budget is spent, looked at every 16 objects: the first of each look loads its picture)
	while _obj_i < n_objs:
		if (_obj_i & 15) == 0 and _obj_i > 0 and float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
		var o: Dictionary = objs[_obj_i]
		var done := false
		var kind := String(o.get("kit", ""))
		if kit and kind != "":
			var facing := String(o.get("facing", o.get("orient", "")))
			var look := TownArt.look(kind, facing, String(o.get("state", "")), int(o.get("variant", 0)))
			if not look.is_empty():
				o["_look"] = look
				var house := int(o.get("in", -1))
				if house >= 0:
					if not house_objs.has(house):
						house_objs[house] = PackedInt32Array()
					house_objs[house].append(_obj_i)
				else:
					var layer := clampi(int(o.layer), 1, 4)
					var cx := clampi(int(float(o.cx)) >> 5, 0, chunks_x - 1)
					var cy := clampi(int(float(o.cy)) >> 5, 0, chunks_y - 1)
					var lists: Array = chunk_objs[cy * chunks_x + cx]
					lists[layer].append(_obj_i)
				done = true
		if not done:
			var layer := int(o.layer)
			var parent: Node2D = layers.get(layer if layer != 5 else 4)
			_add_pieces(parent, o.pieces)
		_obj_i += 1
	_tick("sprites", t1)


func _finish_layers() -> void:
	var t1 := Time.get_ticks_usec()
	_add_pieces(layers[3], d.walls)
	if kit:
		var kd = d.get("kit")
		if kd is Dictionary:
			for w in kd.get("windows", []):
				var cx := clampi(int(w.x) >> 5, 0, chunks_x - 1)
				var cy := clampi(int(w.y) >> 5, 0, chunks_y - 1)
				chunk_wins[cy * chunks_x + cx].append(w)
			var rects: Array = kd.get("houses", [])
			for h in house_objs:
				var r: Array = rects[int(h)] if int(h) < rects.size() else [0, 0, 1, 1]
				var n := TownHousePaint.new()
				n.name = "House%d" % int(h)
				n.setup(self, house_objs[h])
				n.visible = false
				_houses_holder.add_child(n)
				house_nodes[h] = n
				house_rects[h] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_tick("lists", t1)
