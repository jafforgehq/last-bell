## The static map: the ground as one mesh for each terrain, curbs and road markings, and
## every baked prop, wall piece and roof as sprites in draw order. Also owns
## the walkability grids the pathfinding reads.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const GroundDetails := preload("res://scripts/render/ground_details.gd")
const DeckFaces := preload("res://scripts/render/deck_faces.gd")
const TILE := GD.TILE

enum Layer { MARK = 1, LOW = 2, BIG = 4 }
## A ladder opens a barrier tile it comes within this many tiles of.
const LADDER_SLACK := 0.12

var d: Dictionary
var W: int
var H: int
var terrain := PackedByteArray()
var solid_z := PackedByteArray()
var solid_p := PackedByteArray()
## The town only (the generator's `data.shot_low`, scripts/town/prop_heights.gd): 1 on the tiles under a LOW prop (a bed, a sofa, a table, a counter...), shut to walking in `solid_p` and
## `solid_z` but not to a shot, a blow or a look. Empty in every other game (the school, the raid sites): there a solid tile stops a shot as it always did.
var shot_low := PackedByteArray()
var layers := {}
## The tiles of the raised decks (walkways and towers): index to true.
var deck_tiles := {}
## The tiles of the faces of the walkways (their rail and the face that hangs down to the ground, shut to people and the dead
## except at a ladder): index to true. A shot from the ground stops on them (avatar.gd `fire_blocked`).
var deck_face_tiles := {}
var segment_holders := {} # segment id -> Node2D holding its current sprite pieces
var segment_states := {} # segment id -> Array of piece lists, one per damage state
var segment_painters := {} # segment id -> Callable(state): a node that draws that segment's picture itself (the gate)


func build(data: Dictionary) -> void:
	d = data
	W = int(d.W)
	H = int(d.H)
	terrain.resize(W * H)
	solid_z.resize(W * H)
	solid_p.resize(W * H)
	for i in W * H:
		terrain[i] = int(d.terrain[i])
		solid_z[i] = int(d.solidZ[i])
		solid_p[i] = int(d.solidP[i])
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_apply_deck_barriers()

	_build_ground()
	var details := GroundDetails.new()
	details.name = "GroundDetails"
	add_child(details)
	details.setup(self)

	for spec in [["Marks", 1], ["Low", 2], ["Walls", 3], ["Big", 4]]:
		var n := Node2D.new()
		n.name = spec[0]
		n.z_index = spec[1]
		add_child(n)
		layers[spec[1]] = n

	for o in d.objects:
		var layer := int(o.layer)
		var parent: Node2D = layers.get(layer if layer != 5 else 4)
		if o.get("states") != null:
			var holder := Node2D.new()
			holder.name = "Segment%d" % int(o.segment)
			parent.add_child(holder)
			segment_holders[int(o.segment)] = holder
			segment_states[int(o.segment)] = o.states
			_add_pieces(holder, o.states[0])
		else:
			_add_pieces(parent, o.pieces)
	_add_pieces(layers[3], d.walls)
	# the raised platforms get a front face, a shadow and their ladders. The
	# walkways' faces come first in their layer, so the planks draw over their top
	# edge; a tower stands in front of the wall it is built against, so its base
	# comes last in the big layer, over the containers beside it
	var low_faces := DeckFaces.new()
	low_faces.name = "DeckFacesLow"
	low_faces.setup(d, ["walkway"])
	layers[2].add_child(low_faces)
	layers[2].move_child(low_faces, 0)
	var big_faces := DeckFaces.new()
	big_faces.name = "DeckFacesBig"
	big_faces.setup(d, ["tower"])
	layers[4].add_child(big_faces)


## The raised walkways can only be climbed at a ladder. The tiles in front of a
## walkway, where its rail and then its face hang (two rows for the north one),
## are blocked, for people and for the dead, except where a ladder stands; the
## tiles behind them are the deck. The same goes for the column along the inner
## edge of the west and east walkways and the tiles under their south ends. (A
## corner where two walkways meet stays open: it is deck.)
func _apply_deck_barriers() -> void:
	var usable := {}
	var barrier := {}
	for o in d.objects:
		if o.kind != "walkway":
			continue
		var x0 := float(o.cx) - float(o.w) / 2.0
		var x1 := float(o.cx) + float(o.w) / 2.0
		var y0 := float(o.cy) - float(o.h) / 2.0
		var y1 := float(o.cy) + float(o.h) / 2.0
		var c0 := floori(x0)
		var c1 := floori(x1 - 0.001)
		var r0 := floori(y0)
		var r1 := floori(y1 - 0.001)
		if float(o.w) >= float(o.h):
			# along the north wall: the rail is at the south edge and the face hangs
			# below it, down to the ground
			var rail := floori(y1 - 0.05)
			var foot := floori(y1 + DeckFaces.WALKWAY_HEIGHT - 0.2)
			for tx in range(c0, c1 + 1):
				for ty in range(r0, rail):
					usable[ty * W + tx] = true
				for ty in range(rail, foot + 1):
					barrier[ty * W + tx] = true
		else:
			# along the west or east wall: the rail is at the inner edge
			var west: bool = float(o.cx) < float(W) / 2.0
			var rail_c := floori(x1 - 0.05) if west else floori(x0 + 0.05)
			for ty in range(r0, r1 + 1):
				for tx in range(c0, c1 + 1):
					if (west and tx < rail_c) or (not west and tx > rail_c):
						usable[ty * W + tx] = true
				barrier[ty * W + rail_c] = true
			# the short face under its south end
			for ty in range(r1 + 1, floori(y1 + DeckFaces.WALKWAY_HEIGHT - 0.2) + 1):
				for tx in range(c0, c1 + 1):
					barrier[ty * W + tx] = true
	# a ladder opens the barrier wherever its picture reaches
	for o in d.objects:
		if o.kind != "ladder":
			continue
		# w across and h along the ladder as laid out on the map (the ladders on the
		# side walkways lie east to west, so they are the other way round)
		var ex := float(o.w) / 2.0 + LADDER_SLACK
		var ey := float(o.h) / 2.0 + LADDER_SLACK
		for ty in range(floori(float(o.cy) - ey), floori(float(o.cy) + ey) + 1):
			for tx in range(floori(float(o.cx) - ex), floori(float(o.cx) + ex) + 1):
				barrier.erase(ty * W + tx)
	deck_face_tiles = {}
	for i in barrier:
		if usable.has(i):
			continue
		solid_p[i] = 1
		solid_z[i] = 1
		deck_face_tiles[i] = true
	# the towers are raised too
	for o in d.objects:
		if o.kind != "tower":
			continue
		for ty in range(floori(float(o.cy) - float(o.h) / 2.0), floori(float(o.cy) + float(o.h) / 2.0 - 0.001) + 1):
			for tx in range(floori(float(o.cx) - float(o.w) / 2.0), floori(float(o.cx) + float(o.w) / 2.0 - 0.001) + 1):
				usable[ty * W + tx] = true
	deck_tiles = usable


## The ground: one mesh for each kind of terrain instead of a tile map, so the whole ground is a dozen draws rather than some hundreds
## (a tile map draws the tiles of one texture only as long as they are next to each other in its rows). The pictures of a terrain are an
## atlas of 4 x 4 pieces of 128 pixels, and the tile at (x, y) shows the piece (x % 4, y % 4): that is, the ground of a terrain is its
## atlas laid over the world again and again, 4 tiles to a repeat, so each stretch of one terrain is a rectangle drawn with the atlas
## repeating (its UVs run on past 1) and the stretches are the greedy rectangles of the terrain's tiles.
func _build_ground() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	add_child(ground)
	var types := {}
	for type_name in d.terrainTypes:
		var info: Dictionary = d.terrainTypes[type_name]
		types[int(info.id)] = info
	var pieces := {}
	var taken := PackedByteArray()
	taken.resize(W * H)
	for y in H:
		var x := 0
		while x < W:
			var i := y * W + x
			var t := terrain[i]
			if t <= 0 or taken[i] != 0 or not types.has(int(t)):
				x += 1
				continue
			var x1 := x
			while x1 + 1 < W and terrain[i + (x1 + 1 - x)] == t and taken[i + (x1 + 1 - x)] == 0:
				x1 += 1
			var y1 := y
			while y1 + 1 < H:
				var row := (y1 + 1) * W
				var fits := true
				for xx in range(x, x1 + 1):
					if terrain[row + xx] != t or taken[row + xx] != 0:
						fits = false
						break
				if not fits:
					break
				y1 += 1
			for yy in range(y, y1 + 1):
				var row := yy * W
				for xx in range(x, x1 + 1):
					taken[row + xx] = 1
			if not pieces.has(t):
				pieces[t] = PackedInt32Array()
			pieces[t].append_array(PackedInt32Array([x, y, x1 + 1, y1 + 1]))
			x = x1 + 1
	for t in pieces:
		var tex: Texture2D = GD.tex(String(types[t].file))
		var piece_uv := Vector2(128.0 / float(tex.get_width()), 128.0 / float(tex.get_height()))
		var rects: PackedInt32Array = pieces[t]
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for k in range(0, rects.size(), 4):
			var a := Vector2(rects[k], rects[k + 1])
			var b := Vector2(rects[k + 2], rects[k + 3])
			var base := verts.size()
			verts.append_array(PackedVector2Array([a * TILE, Vector2(b.x, a.y) * TILE, b * TILE, Vector2(a.x, b.y) * TILE]))
			uvs.append_array(PackedVector2Array([a * piece_uv, Vector2(b.x, a.y) * piece_uv, b * piece_uv, Vector2(a.x, b.y) * piece_uv]))
			idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
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
		ground.add_child(mi)


func _add_pieces(parent: Node, pieces: Array) -> void:
	for p in pieces:
		var t := GD.tex(p.file)
		var s := Sprite2D.new()
		s.texture = t
		s.centered = false
		s.position = Vector2(p.x, p.y) * TILE
		s.scale = Vector2(p.w * TILE / t.get_width(), p.h * TILE / t.get_height())
		# (the walls of the lots, round 9, may be turned over to face the other way: see lots.gd `_art_for`)
		s.flip_h = bool(p.get("flip_h", false))
		s.flip_v = bool(p.get("flip_v", false))
		parent.add_child(s)


## A wall section made in play (a wall at a mouth of a lot, round 9): drawn from its own four states' pictures,
## in the layer the compound's own sections are in.
func add_segment_art(seg) -> void:
	if seg.art.is_empty() or segment_holders.has(int(seg.id)):
		return
	var holder := Node2D.new()
	holder.name = "Segment%d" % int(seg.id)
	layers[4].add_child(holder)
	segment_holders[int(seg.id)] = holder
	segment_states[int(seg.id)] = seg.art
	_add_pieces(holder, seg.art[0])


func remove_segment_art(seg) -> void:
	var id := int(seg.id)
	if segment_holders.has(id):
		# (out of the tree at once, so that a wall made again at the same place in the same frame has its name and its place)
		var holder: Node2D = segment_holders[id]
		if holder.get_parent() != null:
			holder.get_parent().remove_child(holder)
		holder.queue_free()
		segment_holders.erase(id)
		segment_states.erase(id)


func set_segment_state(id: int, state: int) -> void:
	# a segment whose picture another node draws (the vehicle gate's leaves, scripts/render/gate_node.gd) is told its state
	if segment_painters.has(id):
		segment_painters[id].call(state)
		return
	if not segment_holders.has(id):
		return
	var holder: Node2D = segment_holders[id]
	for c in holder.get_children():
		c.queue_free()
	_add_pieces(holder, segment_states[id][state])


func set_walkable(tiles: Array, open: bool) -> void:
	for i in tiles:
		solid_z[int(i)] = 0 if open else 1
		solid_p[int(i)] = 0 if open else 1


## Whether a point is on a raised deck (a walkway or a tower).
func on_deck(x: float, y: float) -> bool:
	return deck_tiles.has(floori(y) * W + floori(x))


func is_solid(solid: PackedByteArray, x: float, y: float) -> bool:
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return true
	return solid[ty * W + tx] != 0
