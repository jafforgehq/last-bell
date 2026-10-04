## Draws a 24 x 16 tile sample of the town art kit (assets/data/town_art.json) at the game's real tile size (TILE 64 px): a street, a brick house
## cut away (the roof is on its right half only), rooms with furniture, a picket fence, and a fenced yard with the perimeter pieces; saved as a PNG.
## It composes everything FROM THE MANIFEST, the way the town generator will (look an item up by id and by the facing / state / variant it wants,
## draw its rectangle of the picture at the item's anchor). Windowed (headless cannot render), from the repo root:
##
##   Godot --path . --script res://tools/town_art_sample.gd -- --out=/some/dir/town_sample.png [--scale=1.0] [--roof=0|1|2]
##
## --scale: pixels to the tile are 64 x scale (1.0 is the game's own tile size; the game's camera shows 28 to 52 px, so 0.5 to 0.8 is what a player sees).
## --roof: 0 no roof, 1 the roof over the right half (default), 2 the roof over the whole house.
extends SceneTree

const TILE := 64.0
const W := 24
const H := 16

var _man: Dictionary = {}
var _items: Dictionary = {}
var _tex: Dictionary = {}
var _tile_px := 128.0
var _piece_px := 64.0
var _root: Node2D
var _roof_mode := 1


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return default


func _run() -> void:
	var out := _arg("out", "res://town_sample.png")
	var scale := float(_arg("scale", "1.0"))
	_roof_mode = int(_arg("roof", "1"))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town_art.json"))
	_man = parsed
	_tile_px = float(_man.tile_px)
	_piece_px = float(_man.ground_piece_px)
	for it in _man.items:
		_items[String(it.id)] = it
	var vp := SubViewport.new()
	vp.size = Vector2i(int(W * TILE * scale), int(H * TILE * scale))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	_root = Node2D.new()
	_root.scale = Vector2(scale, scale)
	vp.add_child(_root)
	_build()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()


# ------------------------------------------------------------- manifest ---

func _texture(file: String) -> Texture2D:
	if not _tex.has(file):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/town/" + file))
		_tex[file] = ImageTexture.create_from_image(img)
	return _tex[file]


## The sprite of an item with these fields (facing, state, variant, orient, slope): the first that matches.
func _sprite(id: String, want: Dictionary = {}) -> Dictionary:
	var it: Dictionary = _items[id]
	for sp in it.sprites:
		var ok := true
		for k in want:
			if not sp.has(k) or sp[k] != want[k]:
				ok = false
				break
		if ok:
			return sp
	push_error("no sprite %s %s" % [id, str(want)])
	return it.sprites[0]


func _add(sp_rect: Rect2, file: String, pos_tiles: Vector2, z: int, px_per_tile: float, offset_tiles := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _texture(file)
	s.centered = false
	s.region_enabled = true
	s.region_rect = sp_rect
	s.position = (pos_tiles - offset_tiles) * TILE
	s.scale = Vector2.ONE * (TILE / px_per_tile)
	s.z_index = z
	_root.add_child(s)
	return s


## A prop (anything with an anchor and a footprint): its top left footprint cell goes to (cx, cy).
func _prop(id: String, want: Dictionary, cx: float, cy: float, z_override := -1) -> void:
	var it: Dictionary = _items[id]
	var sp := _sprite(id, want)
	var r: Array = sp.rect
	var anchor := Vector2(float(it.anchor[0]), float(it.anchor[1]))
	var z := z_override
	if z < 0:
		var layer := String(it.layer)
		var fp: Array = sp.get("fp", it.footprint)
		z = {"ground": 0, "decal": 10, "wall": 20, "object": 30, "roof": 100}.get(layer, 30)
		if layer == "object":
			z += int(cy + float(fp[1]))
	_add(Rect2(r[0], r[1], r[2], r[3]), String(sp.file), Vector2(cx, cy), z, _tile_px, anchor)


func _ground(id: String, variant: int, cx: int, cy: int) -> void:
	var it: Dictionary = _items[id]
	var sp: Dictionary = it.sprites[variant]
	var px := _piece_px
	_add(Rect2((cx % 4) * px, (cy % 4) * px, px, px), String(sp.file), Vector2(cx, cy), 0, px)


func _cell(id: String, key: String, cx: float, cy: float, z: int) -> void:
	var it: Dictionary = _items[id]
	var sp: Dictionary = it.sprites[0]
	var cp: Array = it.cell_px
	var c: Array = it.cells[key]
	var anchor := Vector2(float(it.anchor[0]), float(it.anchor[1]))
	_add(Rect2(float(c[0]) * cp[0], float(c[1]) * cp[1], cp[0], cp[1]), String(sp.file), Vector2(cx, cy), z, _tile_px, anchor)


func _tile_of(id: String, variant: int, slope := "") -> Dictionary:
	var want := {"variant": variant}
	if slope != "":
		want["slope"] = slope
	return _sprite(id, want)


func _fill(id: String, variant: int, cx: int, cy: int, z: int, slope := "", quarter_ccw := false) -> void:
	var sp := _tile_of(id, variant, slope)
	var r: Array = sp.rect
	var s := _add(Rect2(r[0], r[1], r[2], r[3]), String(sp.file), Vector2(cx, cy), z, _tile_px)
	if quarter_ccw:
		s.rotation = -PI / 2.0
		s.position = Vector2(cx, cy + 1) * TILE


# ----------------------------------------------------------------- scene ---

func _build() -> void:
	var walls := {}
	var doors := {}        # cell -> "door" (not a wall for the edges)
	var roofed := {}
	# the house: x 3..14, y 1..8; a partition at x 9 (y 2..7), one at y 5 (x 10..14) with a doorway at x 13
	for x in range(3, 15):
		for y in range(1, 9):
			if x == 3 or x == 14 or y == 1 or y == 8:
				walls[Vector2i(x, y)] = "brick"
	for y in range(2, 8):
		walls[Vector2i(9, y)] = "plaster"
	for x in range(10, 14):
		walls[Vector2i(x, 5)] = "plaster"
	walls[Vector2i(14, 5)] = "brick"
	walls.erase(Vector2i(13, 5))       # the doorway
	var door_front := Vector2i(6, 8)
	var door_int := Vector2i(9, 3)
	doors[door_front] = true
	doors[door_int] = true
	walls.erase(door_front)
	walls.erase(door_int)
	var windows := {Vector2i(6, 1): "h", Vector2i(11, 1): "h", Vector2i(3, 4): "v", Vector2i(14, 3): "v", Vector2i(11, 8): "h", Vector2i(8, 8): "h", Vector2i(14, 7): "v"}
	var states := {Vector2i(6, 1): "intact", Vector2i(11, 1): "intact", Vector2i(3, 4): "boarded", Vector2i(14, 3): "broken", Vector2i(11, 8): "intact", Vector2i(8, 8): "intact", Vector2i(14, 7): "intact"}

	# ---- the ground
	for y in H:
		for x in W:
			var inside := x > 3 and x < 14 and y > 1 and y < 8
			if inside:
				continue
			if y == 11 or y == 15:
				_ground("sidewalk", (x / 4 + y) % 3, x, y)
			elif y >= 12 and y <= 14:
				_ground("asphalt", (x / 4) % 3, x, y)
			elif x >= 15 and y >= 3 and y <= 8 and x < 16:
				_ground("lawn", 1, x, y)
			else:
				_ground("lawn", ((x / 4) + (y / 4)) % 3, x, y)
	# the gravel drive and the dirt of the fenced yard
	for x in range(17, 23):
		for y in range(4, 8):
			_ground("dirt_path", 1 if (x + y) % 3 == 0 else 0, x, y)
	# ---- the floors
	for y in range(2, 8):
		for x in range(4, 9):
			_ground("floor_wood", 0, x, y)
	for y in range(2, 5):
		for x in range(10, 14):
			_ground("floor_kitchen", 0, x, y)
	for y in range(6, 8):
		for x in range(10, 14):
			_ground("floor_carpet", 1, x, y)
	_ground("floor_wood", 1, 13, 5)
	for x in range(4, 9):
		_ground("floor_runner_h", 0, x, 7)

	# ---- the street: kerb, paint, manholes, a drain
	for x in W:
		_cell("kerb", "s", x, 11, 5)
		_cell("kerb", "n", x, 15, 5)
		_cell("lane_markings", "edge_n", x, 12, 6)
		_cell("lane_markings", "edge_s", x, 14, 6)
		_cell("lane_markings", "double_h", x, 13, 6)
	for x in range(20, 22):
		for y in range(12, 15):
			_cell("lane_markings", "cross_h", x, y, 6)
	_prop("manhole", {"variant": 0}, 11, 12)
	_prop("drain", {"variant": 0, "orient": "h"}, 4, 12)
	_prop("leaves", {"variant": 0}, 3, 11)
	_prop("leaves", {"variant": 2}, 12, 11)
	_prop("leaves", {"variant": 1}, 1, 9)
	_prop("car", {"variant": 2, "orient": "h"}, 6, 12)
	_prop("car_wreck", {"variant": 0}, 15, 12)

	# ---- shadows of the walls on everything next to them (floors, lawn, yard)
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if walls.has(c):
				continue
			var n := walls.has(Vector2i(x, y - 1))
			var w := walls.has(Vector2i(x - 1, y))
			var key := ""
			if n and w:
				key = "nw"
			elif n:
				key = "n"
			elif w:
				key = "w"
			elif walls.has(Vector2i(x - 1, y - 1)):
				key = "diag_nw"
			if key != "":
				_cell("wall_shadows", key, x, y, 4)
	# ---- the wall cells: the fill, then the edges
	for c in walls:
		var mat := String(walls[c])
		var v := 1 if (c.x * 7 + c.y * 3) % 7 == 0 else 0
		var sp := _tile_of("wall_" + mat, v)
		var r: Array = sp.rect
		_add(Rect2(r[0], r[1], r[2], r[3]), String(sp.file), Vector2(c), 20, _tile_px)
		var mask := 0
		for e in [[1, Vector2i(0, -1)], [2, Vector2i(1, 0)], [4, Vector2i(0, 1)], [8, Vector2i(-1, 0)]]:
			if not walls.has(c + e[1]):
				mask |= int(e[0])
		_cell("wall_edges", str(mask), c.x, c.y, 21)
	for c in windows:
		_prop("window", {"orient": windows[c], "state": states[c], "variant": 1 if c.x == 11 else 0}, c.x, c.y, 22)
	_prop("door_front", {"facing": "s", "state": "open", "variant": 0}, door_front.x, door_front.y, 22)
	_prop("door_interior", {"facing": "e", "state": "closed", "variant": 0}, door_int.x, door_int.y, 22)
	# the step in front of the door
	_prop("step", {"facing": "s", "variant": 0}, 5, 9)
	_prop("leaves", {"variant": 2}, 6, 9)

	# ---- furniture: the living room
	_prop("rug_rect", {"facing": "s", "variant": 0}, 4, 4)
	_prop("sofa", {"facing": "s", "variant": 0}, 4, 2)
	_prop("armchair", {"facing": "w", "variant": 1}, 8, 3)
	_prop("tv_stand", {"facing": "n", "variant": 0}, 5, 7)
	_prop("lamp_floor", {"variant": 0}, 8, 2)
	_prop("coffee_table", {"facing": "s", "variant": 0}, 5, 4)
	_prop("blood_stain", {"variant": 1}, 7, 5)
	_prop("papers", {"variant": 0}, 5, 3)
	_prop("bookshelf", {"facing": "e", "state": "closed", "variant": 0}, 4, 5)
	# the kitchen
	_prop("fridge", {"facing": "s", "state": "opened", "variant": 0}, 10, 2)
	_prop("kitchen_counter", {"facing": "s", "state": "closed", "variant": 0}, 11, 2)
	_prop("kitchen_sink", {"facing": "s"}, 12, 2)
	_prop("stove", {"facing": "s", "variant": 0}, 13, 2)
	_prop("dining_table", {"facing": "s", "variant": 0}, 11, 3)
	_prop("chair", {"facing": "n", "variant": 0}, 11, 4)
	_prop("chair", {"facing": "n", "variant": 0}, 12, 4)
	_prop("broken_glass", {"variant": 1}, 10, 4)
	# the bedroom
	_prop("bed_single", {"facing": "s", "variant": 1}, 10, 6)
	_prop("nightstand", {"facing": "s", "state": "opened", "variant": 0}, 11, 6)
	_prop("wardrobe", {"facing": "s", "state": "closed", "variant": 0}, 12, 6)
	_prop("stash_chest", {"facing": "s", "state": "closed"}, 13, 7)
	_prop("dropped_bag", {"variant": 0}, 12, 7)
	_prop("marker_searched", {}, 11.25, 5.9)
	_prop("marker_enter", {"facing": "n"}, 6, 7)

	# ---- the roof over the right half
	if _roof_mode > 0:
		var x0 := 10 if _roof_mode == 1 else 4
		var x1 := 13
		for y in range(2, 8):
			for x in range(x0, x1 + 1):
				roofed[Vector2i(x, y)] = true
		for c in roofed:
			var north: bool = c.y < 5
			var sp2 := _tile_of("roof_terracotta", 1 if (c.x * 5 + c.y) % 9 == 0 else 0, "lit" if north else "shade")
			var r2: Array = sp2.rect
			_add(Rect2(r2[0], r2[1], r2[2], r2[3]), String(sp2.file), Vector2(c), 100, _tile_px)
		var edge_id := "roof_edge_terracotta"
		for c in roofed:
			var m := 0
			for e in [[1, Vector2i(0, -1)], [2, Vector2i(1, 0)], [4, Vector2i(0, 1)], [8, Vector2i(-1, 0)]]:
				if not roofed.has(c + e[1]):
					m |= int(e[0])
			if m != 0:
				_cell(edge_id, str(m), c.x, c.y, 102)
		var rid: Array = _items["roof_terracotta"].ridge
		for x in range(x0, x1 + 1):
			var rr: Array = rid[0].rect
			_add(Rect2(rr[0], rr[1], rr[2], rr[3]), String(rid[0].file), Vector2(x, 4.5), 101, _tile_px)
		_prop("chimney", {"variant": 0}, 12, 3, 103)

	# ---- the front yard: picket fence with a gate, hedge, bushes, trees, a mailbox, bins
	var fence := {}
	for x in range(2, 16):
		fence[Vector2i(x, 10)] = true
	for x in range(2, 16):
		var cmask := 0
		var cc := Vector2i(x, 10)
		if fence.has(cc + Vector2i(1, 0)):
			cmask |= 2
		if fence.has(cc + Vector2i(-1, 0)):
			cmask |= 8
		if x == 6:
			continue
		_cell("fence_picket_white", str(cmask), x, 10, 30 + 10)
	_prop("gate_picket", {"orient": "h", "state": "closed"}, 6, 10, 40)
	var hedge := {}
	for y in range(2, 10):
		hedge[Vector2i(2, y)] = true
	for c in hedge:
		var hm := 0
		if hedge.has(c + Vector2i(0, 1)):
			hm |= 4
		if hedge.has(c + Vector2i(0, -1)):
			hm |= 1
		_cell("hedge", str(hm), c.x, c.y, 35 + c.y)
	_prop("bush", {"variant": 2}, 4, 9)
	_prop("bush", {"variant": 0}, 8, 9)
	_prop("bin", {"variant": 0, "state": "opened"}, 10, 9)
	_prop("mailbox", {"variant": 0, "state": "closed"}, 13, 10)
	_prop("tree", {"variant": 0}, 0, 3)
	_prop("tree", {"variant": 1}, 1, 7)
	_prop("tree", {"variant": 2}, 22, 1)
	_prop("bench", {"facing": "s", "variant": 1}, 20, 9)
	_prop("garden_bed", {"orient": "h", "variant": 0}, 16, 1)
	_prop("swing_set", {"orient": "h"}, 19, 0)
	_prop("bike", {"orient": "h", "variant": 0}, 15, 9)

	# ---- the fenced yard on the right: the perimeter pieces (built on the left, damaged on the right)
	var look_at := func(x: int) -> String: return "built" if x < 20 else "damaged"
	var line := {}
	for x in range(16, 24):
		line[Vector2i(x, 3)] = true
	for y in range(3, 9):
		line[Vector2i(16, y)] = true
	for x in range(16, 24):
		line[Vector2i(x, 8)] = true
	var gate_cells := [Vector2i(18, 8), Vector2i(19, 8)]
	for c in line:
		if c in gate_cells:
			continue
		var lm := 0
		for e in [[1, Vector2i(0, -1)], [2, Vector2i(1, 0)], [4, Vector2i(0, 1)], [8, Vector2i(-1, 0)]]:
			if line.has(c + e[1]):
				lm |= int(e[0])
		var id := "fort_fence_wood_" if c.y == 3 or c.x == 16 else "fort_fence_reinforced_"
		var lk: String = look_at.call(c.x)
		_cell(id + lk, str(lm), c.x, c.y, 30 + c.y + 1)
	_prop("fort_gate", {"orient": "h", "state": "closed", "variant": 0}, 18, 8)
	_prop("fort_tower", {"variant": 0}, 22, 4)
	_prop("floodlight", {"variant": 0}, 17, 5)
	_prop("floodlight", {"variant": 1}, 21, 6)
	for x in range(20, 23):
		var sm := 0
		if x > 20:
			sm |= 8
		if x < 22:
			sm |= 2
		_cell("sandbags_built" if x < 22 else "sandbags_damaged", str(sm), x, 7, 38)
	_prop("shed", {"variant": 0}, 17, 4)
	_prop("barricade_window", {"orient": "v", "variant": 0}, 3, 4, 24)
	_prop("crate", {"variant": 0, "state": "closed"}, 20, 5)
	_prop("box", {"variant": 1, "state": "opened"}, 21, 5)
	_prop("toolbox", {"state": "opened"}, 19, 6)
