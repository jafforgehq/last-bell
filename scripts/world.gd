## The static map: the ground as a TileMapLayer, curbs and road markings, and
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
var layers := {}
## The tiles of the raised decks (walkways and towers): index to true.
var deck_tiles := {}
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
	for i in barrier:
		if usable.has(i):
			continue
		solid_p[i] = 1
		solid_z[i] = 1
	# the towers are raised too
	for o in d.objects:
		if o.kind != "tower":
			continue
		for ty in range(floori(float(o.cy) - float(o.h) / 2.0), floori(float(o.cy) + float(o.h) / 2.0 - 0.001) + 1):
			for tx in range(floori(float(o.cx) - float(o.w) / 2.0), floori(float(o.cx) + float(o.w) / 2.0 - 0.001) + 1):
				usable[ty * W + tx] = true
	deck_tiles = usable


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


## Whether a point is on a raised deck (a walkway or a tower).
func on_deck(x: float, y: float) -> bool:
	return deck_tiles.has(floori(y) * W + floori(x))


func is_solid(solid: PackedByteArray, x: float, y: float) -> bool:
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return true
	return solid[ty * W + tx] != 0
