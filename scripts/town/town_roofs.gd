## The roofs of the town (feature/town-core): one roof for each house, over its walls' rectangle, above the people and the dead (z 7), so that what is inside a house
## is hidden until the avatar is. `update(house_id, dt)` is told which house the avatar stands in (-1: none): that roof fades out over FADE seconds, the others
## are shut; a roof that is clear is not visible at all (it costs nothing).
##
## MODES: "house" (default) a MeshInstance2D for each house (an off-screen roof is culled by the renderer: a draw call for each roof on screen);
## "multi" ONE MultiMeshInstance2D for all of them (one draw call whatever is on screen, the fade is the instance colour: scripts/town/town_roofs.gdshader
## puts the texture on by the world's place so that a roof of any size repeats the atlas as the ground does); "off" none.
## Placeholder roofs: the ROOF and ROOF_LIGHT ground textures of the base map until the town art kit lands (assets/data/town_art.json).
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TILE := GD.TILE
const FADE := 0.25
const Z := 7

var mode := "house"
var houses: Array = []
var _nodes: Array = []
var _alpha := PackedFloat32Array()
var _target := PackedFloat32Array()
var _multi: MultiMeshInstance2D
var _mm: MultiMesh
var _dirty := false
var inside := -1
## How many roofs are not clear now (for the overlay).
var shown := 0


func setup(town: Dictionary, data: Dictionary, roof_mode: String = "house") -> void:
	mode = roof_mode
	houses = town.houses
	z_index = Z
	_alpha.resize(houses.size())
	_alpha.fill(1.0)
	_target.resize(houses.size())
	_target.fill(1.0)
	if mode == "off":
		return
	var tex_a: Texture2D = GD.tex(String(data.terrainTypes.ROOF.file))
	var tex_b: Texture2D = GD.tex(String(data.terrainTypes.ROOF_LIGHT.file))
	if mode == "multi":
		_setup_multi(tex_a)
		return
	for h in houses:
		var r: Rect2i = h.rect
		var tex: Texture2D = tex_a if int(h.id) % 3 != 0 else tex_b
		var piece_uv := Vector2(128.0 / float(tex.get_width()), 128.0 / float(tex.get_height()))
		var a := Vector2(r.position)
		var b := Vector2(r.end)
		var verts := PackedVector2Array([a * TILE, Vector2(b.x, a.y) * TILE, b * TILE, Vector2(a.x, b.y) * TILE])
		var uvs := PackedVector2Array([a * piece_uv, Vector2(b.x, a.y) * piece_uv, b * piece_uv, Vector2(a.x, b.y) * piece_uv])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance2D.new()
		mi.name = "Roof%d" % int(h.id)
		mi.mesh = mesh
		mi.texture = tex
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(mi)
		_nodes.append(mi)
	shown = houses.size()


func _setup_multi(tex: Texture2D) -> void:
	var quad := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = houses.size()
	for h in houses:
		var r: Rect2i = h.rect
		var t := Transform2D(0.0, Vector2(float(r.size.x), float(r.size.y)) * TILE, 0.0, Vector2(r.position) * TILE)
		_mm.set_instance_transform_2d(int(h.id), t)
		_mm.set_instance_color(int(h.id), Color(1, 1, 1, 1))
	_multi = MultiMeshInstance2D.new()
	_multi.name = "Roofs"
	_multi.multimesh = _mm
	_multi.texture = tex
	_multi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/town/town_roofs.gdshader")
	_multi.material = mat
	add_child(_multi)
	shown = houses.size()


## The avatar stands in `house_id` (-1 outside every house): its roof opens.
func update(house_id: int, dt: float) -> void:
	if mode == "off" or houses.is_empty():
		return
	if house_id != inside:
		if inside >= 0:
			_target[inside] = 1.0
		if house_id >= 0:
			_target[house_id] = 0.0
		inside = house_id
		_dirty = true
	if not _dirty:
		return
	var step := dt / FADE
	var moving := false
	var open := 0
	for i in houses.size():
		var a := _alpha[i]
		var t := _target[i]
		if a != t:
			a = move_toward(a, t, step)
			_alpha[i] = a
			_apply(i, a)
			if a != t:
				moving = true
		if a > 0.0:
			open += 1
	shown = open
	_dirty = moving


func _apply(i: int, a: float) -> void:
	if mode == "multi":
		_mm.set_instance_color(i, Color(1, 1, 1, a))
		return
	var n: MeshInstance2D = _nodes[i]
	n.visible = a > 0.01
	n.modulate.a = a
