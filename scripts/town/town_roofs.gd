## The roofs of the town (feature/town-core): one roof for each house, over its walls' rectangle, above the people and the dead (z 7), so that what is inside a house
## is hidden until the avatar is. `update(house_id, dt)` is told which house the avatar stands in (-1: none): that roof fades out over FADE seconds, the others
## are shut; a roof that is clear is not visible at all (it costs nothing).
##
## MODES: "house" (default) a MeshInstance2D for each house (an off-screen roof is culled by the renderer: a draw call for each roof on screen);
## "multi" ONE MultiMeshInstance2D for all of them (one draw call whatever is on screen, the fade is the instance colour: scripts/town/town_roofs.gdshader
## puts the texture on by the world's place so that a roof of any size repeats the atlas as the ground does); "off" none.
## Placeholder roofs: the ROOF and ROOF_LIGHT ground textures of the base map until the town art kit lands (assets/data/town_art.json).
## A house with a `roof_look` ({sign, tint, trim, n}: the raid sites' buildings, scripts/prison/prison_site.gd) gets a flat roof painted over the texture by `paint_look`: a dark outline, the
## parapet trim, panel seams, rooftop units (air conditioners, vents, skylights) and a painted sign (a red cross, a word, a number), with a soft shadow to the south east.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
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
var _first := PackedInt32Array()
var _count := PackedInt32Array()
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
		var tex: Texture2D = tex_a if int(h.id) % 3 != 0 else tex_b
		var piece_uv := Vector2(128.0 / float(tex.get_width()), 128.0 / float(tex.get_height()))
		# one quad for each part of the house (a building of several parts: an L, a T...)
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for pr in _parts_of(h):
			var r: Rect2i = pr
			var a := Vector2(r.position)
			var b := Vector2(r.end)
			var k := verts.size()
			verts.append_array(PackedVector2Array([a * TILE, Vector2(b.x, a.y) * TILE, b * TILE, Vector2(a.x, b.y) * TILE]))
			uvs.append_array(PackedVector2Array([a * piece_uv, Vector2(b.x, a.y) * piece_uv, b * piece_uv, Vector2(a.x, b.y) * piece_uv]))
			idx.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance2D.new()
		mi.name = "Roof%d" % int(h.id)
		mi.mesh = mesh
		mi.texture = tex
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var look = h.get("roof_look")
		if look is Dictionary:    # (a raid site's building: a painted flat roof over the plain one; a child, so it fades with it)
			if look.has("tint"):
				mi.self_modulate = look.tint
			var dn := DrawNode.new()
			dn.painter = func(c): paint_look(c, h)
			mi.add_child(dn)
		add_child(mi)
		_nodes.append(mi)
	shown = houses.size()


## The rectangles of a house's roofs: its `parts`, else its rectangle.
static func _parts_of(h: Dictionary) -> Array:
	var ps = h.get("parts")
	return ps if (ps is Array and not ps.is_empty()) else [h.rect]


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
	# one instance for each part of each house (the first instance of a house is `_first[id]`, `_count[id]` of them)
	var total := 0
	for h in houses:
		total += _parts_of(h).size()
	_mm.instance_count = total
	_first.resize(houses.size())
	_count.resize(houses.size())
	var k := 0
	for h in houses:
		_first[int(h.id)] = k
		var ps := _parts_of(h)
		_count[int(h.id)] = ps.size()
		for pr in ps:
			var r: Rect2i = pr
			var t := Transform2D(0.0, Vector2(float(r.size.x), float(r.size.y)) * TILE, 0.0, Vector2(r.position) * TILE)
			_mm.set_instance_transform_2d(k, t)
			_mm.set_instance_color(k, Color(1, 1, 1, 1))
			k += 1
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
		for k in _count[i]:
			_mm.set_instance_color(_first[i] + k, Color(1, 1, 1, a))
		return
	var n: MeshInstance2D = _nodes[i]
	n.visible = a > 0.01
	n.modulate.a = a


const OUTLINE := Color(0.13, 0.1, 0.08)
const UNIT_GREY := Color(0.62, 0.64, 0.64)
const GLASS := Color(0.43, 0.6, 0.72)


## The painted flat roof of a house with a `roof_look` (world px; drawn once, faded with its roof node). Seeded by the house, so a building always looks the same.
static func paint_look(c: CanvasItem, h: Dictionary) -> void:
	var look: Dictionary = h.roof_look
	var rr: Rect2i = h.rect
	var r := Rect2(Vector2(rr.position) * TILE, Vector2(rr.size) * TILE)
	var trim: Color = look.get("trim", Color(0.78, 0.77, 0.73))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(h.id) * 7919 + rr.position.x * 131 + rr.position.y
	# the shadow on the ground to the south east (the light is top left)
	var sh := Color(0, 0, 0, 0.22)
	c.draw_rect(Rect2(r.end.x, r.position.y + 12.0, 12.0, r.size.y), sh)
	c.draw_rect(Rect2(r.position.x + 12.0, r.end.y, r.size.x, 12.0), sh)
	var inner := r.grow(-16.0)
	# the panel seams across the long way, one every three tiles, and one seam along the middle of a deep roof
	var wide := r.size.x >= r.size.y
	var seam := Color(0, 0, 0, 0.16)
	var lit := Color(1, 1, 1, 0.1)
	var n_seams := int((r.size.x if wide else r.size.y) / (TILE * 3.0))
	for k in range(1, n_seams + 1):
		var t := float(k) * TILE * 3.0
		if wide:
			c.draw_line(Vector2(r.position.x + t, inner.position.y), Vector2(r.position.x + t, inner.end.y), seam, 3.0)
			c.draw_line(Vector2(r.position.x + t + 3.0, inner.position.y), Vector2(r.position.x + t + 3.0, inner.end.y), lit, 2.0)
		else:
			c.draw_line(Vector2(inner.position.x, r.position.y + t), Vector2(inner.end.x, r.position.y + t), seam, 3.0)
			c.draw_line(Vector2(inner.position.x, r.position.y + t + 3.0), Vector2(inner.end.x, r.position.y + t + 3.0), lit, 2.0)
	if minf(r.size.x, r.size.y) >= TILE * 8.0:
		var mid := r.get_center()
		if wide:
			c.draw_line(Vector2(inner.position.x, mid.y), Vector2(inner.end.x, mid.y), seam, 3.0)
		else:
			c.draw_line(Vector2(mid.x, inner.position.y), Vector2(mid.x, inner.end.y), seam, 3.0)
	# the parapet: a trim band round the edge, its inner lip shaded, the dark outline outside it
	c.draw_rect(r.grow(-8.0), trim, false, 16.0)
	c.draw_rect(inner, Color(0, 0, 0, 0.3), false, 3.0)
	c.draw_rect(r.grow(-2.0), Color(1, 1, 1, 0.18), false, 2.0)
	c.draw_rect(r, OUTLINE, false, 4.0)
	# the sign, painted in the middle of a big enough roof
	var sign := String(look.get("sign", ""))
	var side := minf(r.size.x, r.size.y)
	var sign_r := Rect2()
	if sign != "" and side >= TILE * 5.0:
		var s := clampf(side * 0.42, TILE * 2.4, TILE * 9.0)
		if sign == "cross":
			sign_r = Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))
			_paint_cross(c, sign_r)
		else:
			var word := String(look.get("n", "")) if sign == "#" else sign
			var fs := int(clampf(s * (0.8 if sign == "#" else 0.36), 20.0, 150.0))
			var font: Font = ThemeDB.fallback_font
			var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pw := minf(tw + fs * 0.9, inner.size.x - TILE)
			var ph := fs * 1.45
			sign_r = Rect2(r.get_center() - Vector2(pw, ph) * 0.5, Vector2(pw, ph))
			var plate: Color = look.get("plate", Color(0.93, 0.9, 0.82))
			var ink: Color = look.get("ink", Color(0.72, 0.16, 0.14))
			c.draw_rect(sign_r, plate)
			c.draw_rect(sign_r, OUTLINE, false, 4.0)
			c.draw_rect(sign_r.grow(-8.0), Color(ink, 0.6), false, 3.0)
			var base := Vector2(sign_r.get_center().x - tw * 0.5, sign_r.get_center().y + fs * 0.36)
			c.draw_string_outline(font, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, OUTLINE)
			c.draw_string(font, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# the rooftop units: air conditioners, vents and skylights, kept off the sign and off each other
	var area := (r.size.x / TILE) * (r.size.y / TILE)
	var want := clampi(int(area / 32.0), 1, 20)
	var placed: Array = []
	if sign_r.size.x > 0.0:
		placed.append(sign_r.grow(TILE * 0.5))
	var made := 0
	for tries in want * 20:
		if made >= want:
			break
		var kind: String = ["ac", "vent", "sky", "ac", "vent"][made % 5]
		var sz := Vector2(2.0, 1.4) if kind == "ac" else (Vector2(0.9, 0.9) if kind == "vent" else Vector2(1.4, 2.4))
		if kind == "sky" and wide:
			sz = Vector2(sz.y, sz.x)
		sz *= TILE
		var room := inner.grow(-TILE * 0.4)
		if room.size.x < sz.x or room.size.y < sz.y:
			continue
		var at := Vector2(rng.randf_range(room.position.x, room.end.x - sz.x), rng.randf_range(room.position.y, room.end.y - sz.y))
		var ur := Rect2(at, sz)
		var clash := false
		for o in placed:
			if (o as Rect2).intersects(ur.grow(TILE * 0.4)):
				clash = true
				break
		if clash:
			continue
		placed.append(ur)
		made += 1
		_paint_unit(c, ur, kind)


static func _paint_cross(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r, Color(0.95, 0.94, 0.9))
	c.draw_rect(r, OUTLINE, false, 4.0)
	var a := r.size.x * 0.22
	var red := Color(0.8, 0.14, 0.13)
	var h := Rect2(r.position.x + r.size.x * 0.14, r.get_center().y - a * 0.5, r.size.x * 0.72, a)
	var v := Rect2(r.get_center().x - a * 0.5, r.position.y + r.size.y * 0.14, a, r.size.y * 0.72)
	var pts := PackedVector2Array([
		Vector2(v.position.x, v.position.y), Vector2(v.end.x, v.position.y), Vector2(v.end.x, h.position.y), Vector2(h.end.x, h.position.y), Vector2(h.end.x, h.end.y),
		Vector2(v.end.x, h.end.y), Vector2(v.end.x, v.end.y), Vector2(v.position.x, v.end.y), Vector2(v.position.x, h.end.y), Vector2(h.position.x, h.end.y),
		Vector2(h.position.x, h.position.y), Vector2(v.position.x, h.position.y), Vector2(v.position.x, v.position.y)])
	c.draw_colored_polygon(pts, red)
	c.draw_polyline(pts, OUTLINE, 4.0)


static func _paint_unit(c: CanvasItem, r: Rect2, kind: String) -> void:
	c.draw_rect(Rect2(r.position + Vector2(6, 7), r.size), Color(0, 0, 0, 0.28))    # its shadow
	match kind:
		"ac":
			c.draw_rect(r, UNIT_GREY)
			c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.22)), UNIT_GREY.lightened(0.2))
			var f := Vector2(r.position.x + r.size.y * 0.55, r.get_center().y + 2.0)
			var fr := r.size.y * 0.34
			c.draw_circle(f, fr, Color(0.25, 0.26, 0.27))
			for k in 3:
				var ang := float(k) * TAU / 3.0 + 0.4
				c.draw_line(f, f + Vector2.from_angle(ang) * fr * 0.9, UNIT_GREY.darkened(0.2), 4.0)
			c.draw_arc(f, fr, 0, TAU, 20, OUTLINE, 2.0)
			for k in 4:    # the grille
				var gx := r.position.x + r.size.y * 1.05 + float(k) * 7.0
				if gx < r.end.x - 6.0:
					c.draw_line(Vector2(gx, r.position.y + r.size.y * 0.3), Vector2(gx, r.end.y - 8.0), Color(0, 0, 0, 0.35), 2.0)
		"vent":
			c.draw_rect(r, Color(0.48, 0.5, 0.5))
			c.draw_rect(r.grow(-r.size.x * 0.22), Color(0.2, 0.21, 0.22))
			c.draw_line(r.grow(-r.size.x * 0.22).position, r.grow(-r.size.x * 0.22).end, Color(0.48, 0.5, 0.5), 2.0)
		_:
			c.draw_rect(r, Color(0.7, 0.72, 0.72))
			var g := r.grow(-7.0)
			c.draw_rect(g, GLASS)
			c.draw_line(g.position + Vector2(g.size.x * 0.2, g.size.y), g.position + Vector2(g.size.x * 0.75, 0), Color(1, 1, 1, 0.35), 5.0)
			if g.size.x > g.size.y:
				c.draw_line(Vector2(g.get_center().x, g.position.y), Vector2(g.get_center().x, g.end.y), Color(0.7, 0.72, 0.72), 3.0)
			else:
				c.draw_line(Vector2(g.position.x, g.get_center().y), Vector2(g.end.x, g.get_center().y), Color(0.7, 0.72, 0.72), 3.0)
	c.draw_rect(r, OUTLINE, false, 3.0)
