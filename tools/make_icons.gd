## Draws the HUD icons added in round 1 (needs, wounds, trips) with Godot's 2D
## drawing and saves them as white-on-transparent 64x64 PNGs into
## assets/ui/icons, the way the older icons there are: the HUD tints them with
## `modulate`, so the PNGs carry only shape (alpha).
##
## Each icon is drawn on a 64 unit grid with a 6 unit stroke and round caps and
## joins (the older icons are 6 px strokes inside a 3 px margin), rendered at 8x
## in a SubViewport and averaged down, which gives clean edges.
##
## Headless runs cannot render, so run this windowed, from the repo root:
##   Godot --path . --script res://tools/make_icons.gd [-- --only=hungry,thirsty]
## then import the new files: Godot --headless --path . --import
extends SceneTree

const DrawNode := preload("res://scripts/render/draw_node.gd")

const OUT_DIR := "res://assets/ui/icons/"
## The size of the PNGs (the older icons are 64).
const SIZE := 64
## Supersampling: each icon is drawn at SIZE * SS and averaged down.
const SS := 8
## The stroke width on the 64 grid.
const W := 6.0

## The order they are drawn in (and the names of the files).
const NAMES := ["hungry", "thirsty", "starving", "wound", "fever", "down", "resting", "away", "scavenge", "treat", "sendout", "turned"]


## One icon: a list of passes, each a list of shapes. A pass either draws (white)
## or cuts (erases what is under it); a cut pass is how a slash gets a gap
## around it.
class Icon:
	extends RefCounted
	var passes: Array = []

	func _ops() -> Array:
		if passes.is_empty():
			passes.append({"erase": false, "ops": []})
		return passes[passes.size() - 1].ops

	## The shapes after this erase what is under them.
	func cut() -> void:
		passes.append({"erase": true, "ops": []})

	## The shapes after this draw again.
	func ink() -> void:
		passes.append({"erase": false, "ops": []})

	## A stroked polyline with round caps and joins.
	func line(pts: PackedVector2Array, w: float = W) -> void:
		_ops().append({"k": "line", "pts": pts, "w": w})

	## A stroked closed outline.
	func loop(pts: PackedVector2Array, w: float = W) -> void:
		var closed := pts.duplicate()
		closed.append(pts[0])
		_ops().append({"k": "line", "pts": closed, "w": w})

	func disc(c: Vector2, r: float) -> void:
		_ops().append({"k": "disc", "c": c, "r": r})

	## A filled polygon.
	func poly(pts: PackedVector2Array) -> void:
		_ops().append({"k": "poly", "pts": pts})


var _only: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",")
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("make_icons.gd draws on screen: run it without --headless")
		quit(1)
		return
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	for n in NAMES:
		if not _only.is_empty() and not _only.has(n):
			continue
		var icon := Icon.new()
		call("_icon_" + n, icon)
		var img: Image = await _render(icon)
		var err := img.save_png(dir + n + ".png")
		print("%s %s" % ["drew" if err == OK else "FAILED", n])
	quit()


## Draws the icon at SS times its size in a transparent SubViewport and averages
## the alpha down to SIZE x SIZE: white with alpha, like the older icons.
func _render(icon: Icon) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE * SS, SIZE * SS)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	# a cut pass writes transparent black straight over what is there
	var erase_mat := ShaderMaterial.new()
	erase_mat.shader = Shader.new()
	erase_mat.shader.code = "shader_type canvas_item;\nrender_mode blend_disabled;\nvoid fragment() { COLOR = vec4(0.0); }"
	for p in icon.passes:
		var node := DrawNode.new()
		var erase: bool = p.erase
		var ops: Array = p.ops
		node.painter = func(ci: CanvasItem) -> void: _paint(ci, ops, erase)
		if erase:
			node.material = erase_mat
		vp.add_child(node)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var src := vp.get_texture().get_image()
	vp.queue_free()
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var a := 0.0
			for j in SS:
				for i in SS:
					a += src.get_pixel(x * SS + i, y * SS + j).a
			out.set_pixel(x, y, Color(1.0, 1.0, 1.0, a / float(SS * SS)))
	return out


func _paint(ci: CanvasItem, ops: Array, erase: bool) -> void:
	var col := Color(0, 0, 0, 0) if erase else Color.WHITE
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(SS, SS))
	for op in ops:
		match op.k:
			"line":
				var pts: PackedVector2Array = op.pts
				var w: float = op.w
				for i in pts.size() - 1:
					ci.draw_line(pts[i], pts[i + 1], col, w)
				for q in pts:
					ci.draw_circle(q, w * 0.5, col)
			"disc":
				ci.draw_circle(op.c, op.r, col)
			"poly":
				ci.draw_colored_polygon(op.pts, col)


# ------------------------------------------------------------------ geometry --

func _v(x: float, y: float) -> Vector2:
	return Vector2(x, y)


## Points along an arc, angles in degrees (0 right, 90 down, 180 left, 270 up),
## from a0 to a1 (either way round).
func _arc(c: Vector2, r: float, a0: float, a1: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _cubic(p0: Vector2, c0: Vector2, c1: Vector2, p1: Vector2, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(p0 * u * u * u + c0 * 3.0 * u * u * t + c1 * 3.0 * u * t * t + p1 * t * t * t)
	return pts


func _join(parts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for part in parts:
		for q in part:
			if out.is_empty() or out[out.size() - 1].distance_to(q) > 0.001:
				out.append(q)
	return out


## A rounded rectangle outline, corners of radius r.
func _rrect(x0: float, y0: float, x1: float, y1: float, r: float) -> PackedVector2Array:
	return _join([
		_arc(_v(x1 - r, y0 + r), r, 270.0, 360.0, 8),
		_arc(_v(x1 - r, y1 - r), r, 0.0, 90.0, 8),
		_arc(_v(x0 + r, y1 - r), r, 90.0, 180.0, 8),
		_arc(_v(x0 + r, y0 + r), r, 180.0, 270.0, 8),
	])


# -------------------------------------------------------------------- icons --

## A fork and a knife, for hungry (and, crossed out, for starving).
func _cutlery(c: Icon) -> void:
	var fork := _join([[_v(13, 7), _v(13, 23)], _arc(_v(20, 23), 7.0, 180.0, 0.0, 16), [_v(27, 23), _v(27, 7)]])
	c.line(fork, 5.0)
	c.line(PackedVector2Array([_v(20, 29), _v(20, 57)]), W)
	var blade := _join([_cubic(_v(44.5, 6), _v(52, 9), _v(55, 22), _v(53.5, 38)), [_v(44.5, 38)]])
	c.poly(blade)
	c.line(PackedVector2Array([_v(44.5, 6), _v(44.5, 57)]), W)


func _icon_hungry(c: Icon) -> void:
	_cutlery(c)


func _icon_starving(c: Icon) -> void:
	_cutlery(c)
	c.cut()
	c.line(PackedVector2Array([_v(5, 59), _v(59, 5)]), 14.0)
	c.ink()
	c.line(PackedVector2Array([_v(8, 56), _v(56, 8)]), W)


## A tumbler with the water line in it.
func _icon_thirsty(c: Icon) -> void:
	c.loop(PackedVector2Array([_v(13, 8), _v(51, 8), _v(46, 57), _v(18, 57)]), W)
	var wave := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		wave.append(_v(lerpf(16.0, 48.0, t), 28.0 + sin(t * TAU * 1.5) * 2.8))
	c.line(wave, 4.5)


## A solid drop of blood.
func _icon_wound(c: Icon) -> void:
	var ctr := _v(32, 41)
	var r := 17.0
	var apex := _v(32, 3.5)
	var tr := _v(32.0 + r * 0.888, 41.0 - r * 0.46)
	var tl := _v(32.0 - r * 0.888, 41.0 - r * 0.46)
	var pts := _join([
		_cubic(apex, _v(33.5, 14), _v(tr.x, 22.5), tr, 16),
		_arc(ctr, r, -27.4, 207.4, 40),
		_cubic(tl, _v(tl.x, 22.5), _v(30.5, 14), apex, 16),
	])
	c.poly(pts)


## A thermometer with the mercury up.
func _icon_fever(c: Icon) -> void:
	var bulb := _v(26, 46.5)
	var outline := _join([
		_arc(_v(26, 13), 6.0, 180.0, 360.0, 12),
		[_v(32, 13), _v(32, 36.5)],
		_arc(bulb, 11.0, -57.0, 237.0, 34),
		[_v(20, 36.5), _v(20, 13)],
	])
	c.line(outline, 5.5)
	c.disc(bulb, 6.0)
	c.line(PackedVector2Array([bulb, _v(26, 27)]), 4.0)
	c.line(PackedVector2Array([_v(40, 13), _v(50, 13)]), 4.5)
	c.line(PackedVector2Array([_v(40, 22), _v(48, 22)]), 4.5)
	c.line(PackedVector2Array([_v(40, 31), _v(50, 31)]), 4.5)


## Someone lying on the ground, one knee up.
func _icon_down(c: Icon) -> void:
	c.disc(_v(13, 29), 9.0)
	c.line(PackedVector2Array([_v(26, 33), _v(45, 33)]), 12.0)
	c.line(PackedVector2Array([_v(45, 33), _v(52, 19), _v(59, 33)]), 7.0)
	c.line(PackedVector2Array([_v(7, 50), _v(57, 50)]), 5.0)


## A big Z and a small z: asleep.
func _icon_resting(c: Icon) -> void:
	c.line(PackedVector2Array([_v(30, 9), _v(56, 9), _v(30, 36), _v(56, 36)]), W)
	c.line(PackedVector2Array([_v(7, 42), _v(23, 42), _v(7, 57), _v(23, 57)]), 5.5)


## An arrow leaving a box: out of the compound.
func _icon_away(c: Icon) -> void:
	c.line(PackedVector2Array([_v(28, 13), _v(11, 13), _v(11, 53), _v(51, 53), _v(51, 36)]), W)
	c.line(PackedVector2Array([_v(27, 37), _v(53, 11)]), W)
	c.line(PackedVector2Array([_v(37, 10), _v(54, 10), _v(54, 27)]), W)


## A backpack.
func _icon_scavenge(c: Icon) -> void:
	c.line(_arc(_v(32, 15), 7.0, 180.0, 360.0, 14), W)
	var body := _join([
		_arc(_v(27, 28), 15.0, 180.0, 270.0, 10),
		_arc(_v(37, 28), 15.0, 270.0, 360.0, 10),
		_arc(_v(45, 52), 6.0, 0.0, 90.0, 8),
		_arc(_v(19, 52), 6.0, 90.0, 180.0, 8),
	])
	c.loop(body, W)
	c.line(PackedVector2Array([_v(12, 33), _v(52, 33)]), 4.5)
	c.loop(_rrect(22, 40, 42, 53, 4), 4.5)


## An adhesive bandage.
func _icon_treat(c: Icon) -> void:
	var ctr := _v(32, 32)
	var rot := deg_to_rad(-45.0)
	var out := PackedVector2Array()
	for q in _rrect(-26, -11, 26, 11, 11):
		out.append(ctr + q.rotated(rot))
	c.loop(out, W)
	for x in [-8.0, 8.0]:
		c.line(PackedVector2Array([ctr + _v(x, -9).rotated(rot), ctr + _v(x, 9).rotated(rot)]), 4.5)


## A door with an arrow going out through it.
func _icon_sendout(c: Icon) -> void:
	c.line(PackedVector2Array([_v(27, 8), _v(10, 8), _v(10, 56), _v(27, 56)]), W)
	c.line(PackedVector2Array([_v(24, 32), _v(56, 32)]), W)
	c.line(PackedVector2Array([_v(43, 19), _v(56, 32), _v(43, 45)]), W)


## A skull, cracked: one of the dead now.
func _icon_turned(c: Icon) -> void:
	var skull := _join([
		_arc(_v(32, 27), 20.0, 180.0, 360.0, 24),
		[_v(52, 40), _v(44, 43), _v(44, 57), _v(20, 57), _v(20, 43), _v(12, 40)],
	])
	c.loop(skull, W)
	c.disc(_v(23.5, 33), 5.0)
	c.disc(_v(40.5, 33), 5.0)
	c.line(PackedVector2Array([_v(28, 49), _v(28, 56)]), 4.5)
	c.line(PackedVector2Array([_v(36, 49), _v(36, 56)]), 4.5)
	# the crack breaks the outline at the top right and runs down to the eye
	c.cut()
	c.line(PackedVector2Array([_v(45, 4), _v(40, 14)]), 6.5)
	c.ink()
	c.line(PackedVector2Array([_v(42.5, 8), _v(36.5, 17), _v(42, 22), _v(37, 27.5)]), 3.5)
