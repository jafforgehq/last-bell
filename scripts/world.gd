## The static map: the ground as a TileMapLayer, curbs and road markings, and
## every baked prop, wall piece and roof as sprites in draw order. Also owns
## the walkability grids the pathfinding reads.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const GroundDetails := preload("res://scripts/render/ground_details.gd")
const TILE := GD.TILE

enum Layer { MARK = 1, LOW = 2, BIG = 4 }

var d: Dictionary
var W: int
var H: int
var terrain := PackedByteArray()
var solid_z := PackedByteArray()
var solid_p := PackedByteArray()
var layers := {}
var segment_holders := {} # segment id -> Node2D holding its current sprite pieces
var segment_states := {} # segment id -> Array of piece lists, one per damage state


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


func _build_ground() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(128, 128)
	for type_name in d.terrainTypes:
		var info: Dictionary = d.terrainTypes[type_name]
		var src := TileSetAtlasSource.new()
		src.texture = GD.tex(info.file)
		src.texture_region_size = Vector2i(128, 128)
		for y in 4:
			for x in 4:
				src.create_tile(Vector2i(x, y))
		ts.add_source(src, int(info.id))
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = ts
	ground.scale = Vector2(0.5, 0.5)
	add_child(ground)
	for y in H:
		for x in W:
			var t := terrain[y * W + x]
			if t > 0:
				ground.set_cell(Vector2i(x, y), t, Vector2i(x % 4, y % 4))


func _add_pieces(parent: Node, pieces: Array) -> void:
	for p in pieces:
		var t := GD.tex(p.file)
		var s := Sprite2D.new()
		s.texture = t
		s.centered = false
		s.position = Vector2(p.x, p.y) * TILE
		s.scale = Vector2(p.w * TILE / t.get_width(), p.h * TILE / t.get_height())
		parent.add_child(s)


func set_segment_state(id: int, state: int) -> void:
	var holder: Node2D = segment_holders[id]
	for c in holder.get_children():
		c.queue_free()
	_add_pieces(holder, segment_states[id][state])


func set_walkable(tiles: Array, open: bool) -> void:
	for i in tiles:
		solid_z[int(i)] = 0 if open else 1
		solid_p[int(i)] = 0 if open else 1


func is_solid(solid: PackedByteArray, x: float, y: float) -> bool:
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return true
	return solid[ty * W + tx] != 0
