## The live parts of a figure (the ground shadow, legs and shoes, a walker's reaching arms, the hands on a
## weapon) baked into meshes, so a figure on screen costs a handful of cheap draws instead of forty-odd
## polygon commands.
##
## Why: every `draw_colored_polygon`, `draw_polyline` and `draw_circle` the canvas is given costs about ten
## microseconds of the CPU (it builds vertex buffers for the command), and a walker used to be 41 of them every
## frame: 80 of the dead in view was 40 ms of drawing and 4,000 draw calls. A mesh that already exists costs
## about one microsecond to draw again, and the same mesh is shared by every figure of a kind.
##
## What: pawn_art.gd stays the one place that says what the parts look like. Here its own functions are run
## once into a `Baker` (a stand-in for the canvas that, instead of drawing, writes triangles), for a few
## dozen poses of the stride and of the claw, and the pose nearest to the figure's is drawn. The colours of the
## figure (trousers, shoes, sleeves, skin) are not in the mesh: the mesh points at a little palette texture
## with one texel for each (`palette_texture`), so one mesh serves every look. The outline strokes get a thin
## soft edge of their own (FEATHER), standing in for the canvas's antialiasing.
##
## The bodies (baked sprites), the weapons and the poses at work are not touched.
extends RefCounted

const Art := preload("res://scripts/render/pawn_art.gd")

## How many poses of the stride (a full turn of the walk phase) and of the claw are baked. 32 steps move a
## runner's foot by under two pixels at a time at the usual zoom.
const LEG_STEPS := 32
const ARM_STEPS := 24
## The palette's texels, and which colour of `Art.palette` (or of the pawn art's constants) each one holds.
const SLOT_INK := 0
const SLOT_SHADOW := 1
const SLOT_PANTS := 2
const SLOT_PANTS_BACK := 3
const SLOT_SHOE := 4
const SLOT_SHOE_BACK := 5
const SLOT_SLEEVE := 6
const SLOT_SKIN := 7
const SLOTS := 8
## The soft edge of an outline stroke, in tiles (about a pixel at the usual zoom).
const FEATHER := 0.02
## How a stroke's corner is allowed to stretch (the longest miter, as a multiple of half the width).
const MITER_LIMIT := 2.5
const CIRCLE_SEGMENTS := 14

static var _palettes := {}
static var _legs := {}
static var _arms := {}
static var _hands := {}
static var _bake_pal := {}
static var _kids := {}


## What `Art.palette` returns, with each colour standing for a texel: the baker reads the slot back from the
## colour it is drawn with (the colours are only ever compared, never shown).
static func bake_palette() -> Dictionary:
	if _bake_pal.is_empty():
		_bake_pal = {
			"pants": _slot_color(SLOT_PANTS),
			"pants_back": _slot_color(SLOT_PANTS_BACK),
			"shoe": _slot_color(SLOT_SHOE),
			"shoe_back": _slot_color(SLOT_SHOE_BACK),
			"sleeve": _slot_color(SLOT_SLEEVE),
			"skin": _slot_color(SLOT_SKIN),
		}
	return _bake_pal


static func _slot_color(slot: int) -> Color:
	return Color((float(slot) + 0.5) / float(SLOTS), 0.25, 0.75, 1.0)


## The texture a figure's meshes are drawn with: one texel per slot, in the colours of its palette.
static func palette_texture(pal: Dictionary) -> Texture2D:
	var cols: Array[Color] = [Art.INK, Art.SHADOW_COL, pal.pants, pal.pants_back, pal.shoe, pal.shoe_back, pal.sleeve, pal.skin]
	var key := ""
	for c in cols:
		key += c.to_html(false)
	if _palettes.has(key):
		return _palettes[key]
	var img := Image.create(SLOTS, 1, false, Image.FORMAT_RGBA8)
	for i in SLOTS:
		var c := cols[i]
		c.a = 1.0 # (the strength of each stroke is in the mesh's own vertex colours)
		img.set_pixel(i, 0, c)
	var tex := ImageTexture.create_from_image(img)
	_palettes[key] = tex
	return tex


## A number for a kind (a kind this file does not know is drawn as a walker, so it is a walker's number).
static func _kid(kind: String) -> int:
	if _kids.is_empty():
		var i := 0
		for k in Art.STYLES:
			_kids[k] = i
			i += 1
	return _kids.get(kind, 0)


static func _bucket(phase: float, steps: int) -> int:
	return int(fposmod(phase, TAU) * (float(steps) / TAU) + 0.5) % steps


# ----------------------------------------------------------------- legs --

## The shadow (when `shadow`) and the legs of a figure of a kind, in the stride's pose nearest `phase`
## (a figure that is not `moving` stands: one pose). `view` is the figure's view: E, S or N (S and N differ in which way the feet come forward).
## The mesh is in tiles from where the figure stands, in the colours of `palette_texture`.
static func legs(kind: String, view: String, phase: float, moving: bool, limp: bool, shadow: bool) -> ArrayMesh:
	var east := view == "E"
	var north := view == "N"
	var b := _bucket(phase, LEG_STEPS) if moving else 0
	var key := ((_kid(kind) * 2 + int(east)) * 2 + int(moving)) * 2 + int(limp)
	key = ((key * 2 + int(shadow)) * 2 + int(north)) * 64 + b
	if _legs.has(key):
		return _legs[key]
	var st := Art.style(kind)
	var bk := Baker.new()
	if shadow:
		Art.shadow(bk, st)
	Art.legs(bk, bake_palette(), "E" if east else ("N" if north else "S"), float(b) * TAU / float(LEG_STEPS), moving, limp, 1.0, st)
	var mesh := bk.mesh()
	_legs[key] = mesh
	return mesh


static var _shadows := {}


## ANIM: the ground shadow of a kind alone (one mesh a kind), for a figure whose body is not on its feet (one that is falling): drawn by itself so that it can stay put and fade
## while the body goes over.
static func shadow(kind: String) -> ArrayMesh:
	if _shadows.has(kind):
		return _shadows[kind]
	var bk := Baker.new()
	Art.shadow(bk, Art.style(kind))
	var mesh := bk.mesh()
	_shadows[kind] = mesh
	return mesh


# ----------------------------------------------------------------- arms --

## The arms of one layer ("back": drawn before the body, "front": after) of a figure of a kind, in the pose
## nearest: the claw's when `attacking`, a sprinter's stride's (`phase`) for a kind that runs, else at rest.
## Null when the view has no arm in that layer.
static func arms(kind: String, view: String, layer: String, t: float, attacking: bool, phase: float) -> ArrayMesh:
	var st := Art.style(kind)
	var sprint: bool = st.pose == "sprint" and not attacking
	var b := 0
	if sprint:
		b = _bucket(phase, LEG_STEPS)
	elif attacking:
		b = _bucket(t * 7.0 * float(st.claw_rate), ARM_STEPS)
	var key := ((((_kid(kind)) * 3 + (0 if view == "S" else (1 if view == "E" else 2))) * 2 + int(layer == "front")) * 3 + (0 if not attacking and not sprint else (1 if attacking else 2))) * 64 + b
	if _arms.has(key):
		return _arms[key]
	var bk := Baker.new()
	var tt := 1.2083 # at rest: the pose where the slow sway of the hand is at its middle
	if attacking:
		tt = float(b) * TAU / float(ARM_STEPS) / (7.0 * float(st.claw_rate))
	Art.arms(bk, bake_palette(), view, tt, attacking, layer, st, float(b) * TAU / float(LEG_STEPS))
	var mesh: ArrayMesh = bk.mesh() if not bk.is_empty() else null
	_arms[key] = mesh
	return mesh


## The two hands on a weapon (`front`: how far forward the second is, or null for one).
static func hands(front) -> ArrayMesh:
	var key: float = -1000.0 if front == null else float(front)
	if _hands.has(key):
		return _hands[key]
	var bk := Baker.new()
	Art.hands(bk, front, bake_palette().skin)
	var mesh := bk.mesh()
	_hands[key] = mesh
	return mesh


## How many meshes are baked so far (a test's, and a hint for a warm-up).
static func baked() -> int:
	return _legs.size() + _arms.size() + _hands.size()


# ---------------------------------------------------------------- baker --

## Stands in for the canvas where the figure's parts are drawn (anything with its draw_* methods will do for
## pawn_art.gd): writes triangles into arrays. Every vertex carries the texel of its colour in its UVs and the
## colour's strength (and the stroke's soft edge) in its alpha.
class Baker:
	extends RefCounted
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func draw_set_transform_matrix(_m: Transform2D) -> void:
		pass # (the parts are baked where they stand; the figure's own transform is the mesh's when it is drawn)

	func is_empty() -> bool:
		return idx.is_empty()

	## The slot a colour stands for: the palette's stand-ins, the ink, or else the shadow.
	func _slot(c: Color) -> int:
		if absf(c.g - 0.25) < 0.001 and absf(c.b - 0.75) < 0.001:
			return clampi(int(c.r * float(SLOTS)), 0, SLOTS - 1)
		if absf(c.r - Art.INK.r) < 0.002 and absf(c.g - Art.INK.g) < 0.002 and absf(c.b - Art.INK.b) < 0.002:
			return SLOT_INK
		return SLOT_SHADOW

	func _vertex(p: Vector2, slot: int, a: float) -> int:
		verts.append(p)
		uvs.append(Vector2((float(slot) + 0.5) / float(SLOTS), 0.5))
		cols.append(Color(1.0, 1.0, 1.0, a))
		return verts.size() - 1

	## A convex polygon, as a fan.
	func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs = null, _tex = null) -> void:
		var n := pts.size()
		if n < 3:
			return
		var slot := _slot(col)
		var first := _vertex(pts[0], slot, col.a)
		var prev := _vertex(pts[1], slot, col.a)
		for i in range(2, n):
			var cur := _vertex(pts[i], slot, col.a)
			idx.append_array(PackedInt32Array([first, prev, cur]))
			prev = cur

	func draw_circle(c: Vector2, r: float, col: Color, _filled = true, _width = -1.0, _aa = false) -> void:
		var slot := _slot(col)
		var centre := _vertex(c, slot, col.a)
		var first := -1
		var prev := -1
		for i in CIRCLE_SEGMENTS:
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			var cur := _vertex(c + Vector2(cos(a), sin(a)) * r, slot, col.a)
			if first < 0:
				first = cur
			else:
				idx.append_array(PackedInt32Array([centre, prev, cur]))
			prev = cur
		idx.append_array(PackedInt32Array([centre, prev, first]))

	func draw_line(a: Vector2, b: Vector2, col: Color, width: float = -1.0, aa: bool = false) -> void:
		draw_polyline(PackedVector2Array([a, b]), col, width, aa)

	## A stroke of `width` with mitered corners and a soft edge on each side (the canvas's antialiasing).
	func draw_polyline(pts: PackedVector2Array, col: Color, width: float = -1.0, _aa: bool = false) -> void:
		var n := pts.size()
		if n < 2:
			return
		var closed := n > 2 and pts[0].is_equal_approx(pts[n - 1])
		var m := n - 1 if closed else n
		var slot := _slot(col)
		var half := maxf(width, 0.01) * 0.5
		var core := maxf(half - FEATHER * 0.5, 0.0)
		var outer := half + FEATHER * 0.5
		var base := verts.size()
		for i in m:
			var p := pts[i]
			var has_prev := closed or i > 0
			var has_next := closed or i < m - 1
			var d0 := Vector2.ZERO
			var d1 := Vector2.ZERO
			if has_prev:
				d0 = (p - pts[(i - 1 + m) % m]).normalized()
			if has_next:
				d1 = (pts[(i + 1) % m] - p).normalized()
			if not has_prev:
				d0 = d1
			if not has_next:
				d1 = d0
			var n0 := Vector2(-d0.y, d0.x)
			var n1 := Vector2(-d1.y, d1.x)
			var mit := n0 + n1
			var off := n0
			if mit.length_squared() > 0.0001:
				mit = mit.normalized()
				off = mit / maxf(mit.dot(n0), 1.0 / MITER_LIMIT)
			_vertex(p - off * outer, slot, 0.0)
			_vertex(p - off * core, slot, col.a)
			_vertex(p + off * core, slot, col.a)
			_vertex(p + off * outer, slot, 0.0)
		var segs := m if closed else m - 1
		for i in segs:
			var a := base + i * 4
			var b := base + ((i + 1) % m) * 4
			for k in 3:
				idx.append_array(PackedInt32Array([a + k, a + k + 1, b + k, a + k + 1, b + k + 1, b + k]))

	func mesh() -> ArrayMesh:
		var out := ArrayMesh.new()
		if idx.is_empty():
			return out
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out
