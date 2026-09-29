## In-world labels drawn at screen size: names under people, health and
## reload rings, wall damage bars, selection brackets, range circle and the
## move-order marker.
extends Node2D

const S := preload("res://scripts/render/shapes.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const TILE := 64.0
const ACCENT := Color(0.941, 0.761, 0.29)

var main


func _screen(x: float, y: float) -> Vector2:
	return get_viewport().get_canvas_transform() * (Vector2(x, y) * TILE)


func _pill(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, rect.size.y * 0.5, 5), color)


func _dashed_circle(c: Vector2, r: float, color: Color, width: float) -> void:
	var n := maxi(12, int(TAU * r / 10.0))
	for i in n:
		var a0 := TAU * i / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.4, 4, color, width, true)


func _dashed_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dist := a.distance_to(b)
	var t := 0.0
	while t < dist:
		var t1 := minf(dist, t + 6.0)
		draw_line(a.lerp(b, t / dist), a.lerp(b, t1 / dist), color, width, true)
		t += 11.0


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim = main.sim
	var z: float = main.zoom_px
	var vp := get_viewport_rect().size
	var sel = main.selection

	# wall damage bars across the damaged piece
	for s in sim.segments:
		if s.hp >= s.max_hp * 0.95:
			continue
		var p := _screen(s.obj.cx, s.obj.cy)
		if p.x < -60 or p.y < -60 or p.x > vp.x + 60 or p.y > vp.y + 60:
			continue
		var w := clampf((s.to - s.from) * z * 0.45, 28.0, 80.0)
		var f: float = s.hp / s.max_hp
		_pill(Rect2(p.x - w / 2 - 2, p.y - 3.5, w + 4, 7), Color(14 / 255.0, 12 / 255.0, 10 / 255.0, 0.78))
		var col := Color("#e0584a") if f < 0.34 else (Color("#e8953a") if f < 0.67 else Color("#9cc46a"))
		_pill(Rect2(p.x - w / 2, p.y - 1.5, maxf(3.0, w * f), 3), col)

	# selection
	if sel != null and (sel.kind == "person" or sel.kind == "zombie"):
		var e = sel.ref
		if not (sel.kind == "zombie" and e.state == "dead"):
			var a := _screen(e.x - 0.48, e.y - 0.92)
			var b := _screen(e.x + 0.48, e.y + 0.42)
			var L := maxf(5.0, (b.x - a.x) * 0.22)
			var col := ACCENT if sel.kind == "person" else Color("#e2685a")
			for c in [[a.x, a.y, 1, 1], [b.x, a.y, -1, 1], [a.x, b.y, 1, -1], [b.x, b.y, -1, -1]]:
				draw_polyline(PackedVector2Array([Vector2(c[0] + c[2] * L, c[1]), Vector2(c[0], c[1]), Vector2(c[0], c[1] + c[3] * L)]), col, 2.0, true)
			if sel.kind == "person" and not e.downed:
				_dashed_circle(_screen(e.x, e.y), float(e.gun.range) * z, Color(ACCENT, 0.35), 1.2)
	elif sel != null and sel.kind == "segment":
		var o: Dictionary = sel.ref.obj
		var hw: float = absf(cos(o.a)) * o.w / 2.0 + absf(sin(o.a)) * o.h / 2.0
		var hh: float = absf(sin(o.a)) * o.w / 2.0 + absf(cos(o.a)) * o.h / 2.0
		var a := _screen(o.cx - hw, o.cy - hh)
		var b := _screen(o.cx + hw, o.cy + hh)
		for edge in [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b], [b, Vector2(a.x, b.y)], [Vector2(a.x, b.y), a]]:
			_dashed_line(edge[0], edge[1], ACCENT, 2.0)
	var hover = main.hover
	if hover != null and (sel == null or hover != sel.ref):
		var a := _screen(hover.x - 0.45, hover.y - 0.88)
		draw_rect(Rect2(a, Vector2(0.9, 1.28) * z), Color(1, 1, 1, 0.35), false, 1.0)

	# move order marker
	var om = main.order_mark
	if om != null and main.clock - om.t < 0.7:
		var k: float = (main.clock - om.t) / 0.7
		draw_arc(_screen(om.x, om.y), (0.2 + k * 0.5) * z, 0, TAU, 32, Color(ACCENT, 1.0 - k), 2.0, true)

	# names under people
	if z >= 16.0:
		var font := Fonts.cond(600)
		var fs := 12 if z >= 34.0 else 11
		for p in sim.people:
			var pos := _screen(p.x, p.y + 0.52)
			if pos.x < -40 or pos.x > vp.x + 40 or pos.y < -20 or pos.y > vp.y + 20:
				continue
			var label: String = p.first
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
			var selected: bool = sel != null and sel.ref == p
			var bg := Color(ACCENT, 0.92) if selected else (Color(46 / 255.0, 40 / 255.0, 24 / 255.0, 0.86) if p.drafted else Color(16 / 255.0, 14 / 255.0, 12 / 255.0, 0.72))
			_pill(Rect2(pos.x - tw / 2, pos.y - 8, tw, 16), bg)
			var fg := Color("#1a1610") if selected else (ACCENT if p.drafted else Color("#ece6d8"))
			draw_string(font, Vector2(pos.x - tw / 2, pos.y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, tw, fs, fg)
			if p.hp < 100.0:
				draw_rect(Rect2(pos.x - 14, pos.y + 10, 28, 4), Color(14 / 255.0, 12 / 255.0, 10 / 255.0, 0.8))
				draw_rect(Rect2(pos.x - 13.5, pos.y + 10.5, 27.0 * p.hp / 100.0, 3), Color("#d0493a") if p.hp < 35 else Color("#8fb85a"))
			if p.reloading > 0.0:
				var k: float = 1.0 - p.reloading / float(p.gun.reload)
				var hy := _screen(p.x, p.y - 0.53 - 0.45).y
				draw_arc(Vector2(pos.x, hy), 6, 0, TAU, 24, Color(14 / 255.0, 12 / 255.0, 10 / 255.0, 0.7), 3.5, true)
				draw_arc(Vector2(pos.x, hy), 6, -PI / 2, -PI / 2 + k * TAU, 24, ACCENT, 2.0, true)
