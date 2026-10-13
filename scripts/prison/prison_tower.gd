## The prison watchtowers, drawn in code: a deck layer (below the guard) and a roof layer (above him).
## The footprint is the 3 x 3 tile Rect2 from prison_base.gd; the guard stands at its centre.
const T := 64.0
const INK := Color(0.12, 0.08, 0.05)
const WOOD := Color(0.47, 0.35, 0.22)
const WOOD_D := Color(0.36, 0.26, 0.16)
const WOOD_L := Color(0.58, 0.45, 0.29)
const TARP := Color(0.36, 0.42, 0.28)


static func lamp_pos(r: Rect2) -> Vector2:
	return (r.position + Vector2(2.7, 0.35)) * T


## Ground shadow, legs, cross-brace, deck with planks, rail with a gap, ladder, post marker.
static func draw_deck(c: CanvasItem, r: Rect2) -> void:
	var o := r.position * T
	var d := Rect2(o + Vector2(0.2, 0.15) * T, Vector2(2.6, 2.6) * T)
	# soft shadow, thrown to the south-east so the tower reads as tall
	var sh := PackedVector2Array()
	for q in [d.position, Vector2(d.end.x, d.position.y), d.end, Vector2(d.position.x, d.end.y)]:
		sh.append(q + Vector2(0.45, 0.55) * T)
	c.draw_colored_polygon(sh, Color(0, 0, 0, 0.26))
	# front face with legs and an X brace
	var fy := d.end.y
	var fh := 0.5 * T
	c.draw_rect(Rect2(d.position.x, fy, d.size.x, fh), WOOD_D)
	c.draw_line(Vector2(d.position.x + 0.2 * T, fy), Vector2(d.end.x - 0.2 * T, fy + fh), INK, 3.0)
	c.draw_line(Vector2(d.end.x - 0.2 * T, fy), Vector2(d.position.x + 0.2 * T, fy + fh), INK, 3.0)
	c.draw_rect(Rect2(d.position.x, fy, d.size.x, fh), INK, false, 3.0)
	for lx in [d.position.x - 0.05 * T, d.end.x - 0.15 * T]:
		c.draw_rect(Rect2(lx, fy - 0.05 * T, 0.2 * T, fh + 0.1 * T), WOOD)
		c.draw_rect(Rect2(lx, fy - 0.05 * T, 0.2 * T, fh + 0.1 * T), INK, false, 2.5)
	# deck with plank lines
	c.draw_rect(d, WOOD_L)
	for k in range(1, 8):
		var y := d.position.y + d.size.y * float(k) / 8.0
		c.draw_line(Vector2(d.position.x, y), Vector2(d.end.x, y), WOOD_D, 2.0)
		c.draw_line(Vector2(d.position.x + (0.5 + float(k % 3) * 0.5) * T, y - d.size.y / 8.0), Vector2(d.position.x + (0.5 + float(k % 3) * 0.5) * T, y), WOOD_D, 1.5)
	c.draw_rect(d, INK, false, 3.0)
	# the marked post: a plate and a ring under the guard's feet
	var m := r.get_center() * T
	c.draw_rect(Rect2(m - Vector2(0.5, 0.35) * T, Vector2(1.0, 0.7) * T), Color(0.3, 0.22, 0.13, 0.85))
	c.draw_arc(m, 0.42 * T, 0, TAU, 28, Color(0.95, 0.8, 0.3, 0.8), 3.0)
	c.draw_rect(Rect2(m - Vector2(0.5, 0.35) * T, Vector2(1.0, 0.7) * T), INK, false, 2.0)
	# rail: three sides and the front, with a gap at the ladder
	var gx := d.end.x - 0.95 * T
	var rl := Color(0.62, 0.5, 0.33)
	for seg in [
		[d.position, Vector2(d.end.x, d.position.y)],
		[d.position, Vector2(d.position.x, d.end.y)],
		[Vector2(d.end.x, d.position.y), d.end],
		[Vector2(d.position.x, d.end.y), Vector2(gx - 0.3 * T, d.end.y)],
		[Vector2(gx + 0.3 * T, d.end.y), d.end],
	]:
		c.draw_line(seg[0], seg[1], INK, 8.0)
		c.draw_line(seg[0], seg[1], rl, 4.5)
	for q in [d.position, Vector2(d.end.x, d.position.y), d.end, Vector2(d.position.x, d.end.y), Vector2(gx - 0.3 * T, d.end.y), Vector2(gx + 0.3 * T, d.end.y)]:
		c.draw_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), WOOD_D)
		c.draw_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), INK, false, 2.0)
	# ladder down the front through the gap
	var ly := fy + fh + 0.2 * T
	for sx in [gx - 0.18 * T, gx + 0.18 * T]:
		c.draw_line(Vector2(sx, d.end.y - 0.1 * T), Vector2(sx, ly), INK, 6.0)
		c.draw_line(Vector2(sx, d.end.y - 0.1 * T), Vector2(sx, ly), WOOD, 3.0)
	for k in 5:
		var y2 := lerpf(d.end.y, ly, (float(k) + 0.5) / 5.0)
		c.draw_line(Vector2(gx - 0.18 * T, y2), Vector2(gx + 0.18 * T, y2), INK, 3.0)


## Tarp on the west side (clear of the guard), the floodlight mast and its lamp. night 0..1.
static func draw_roof(c: CanvasItem, r: Rect2, night: float) -> void:
	var o := r.position * T
	var tl := o + Vector2(0.0, 0.0) * T
	var poly := PackedVector2Array([tl + Vector2(0.0, 0.05) * T, tl + Vector2(1.1, 0.0) * T, tl + Vector2(1.1, 1.75) * T, tl + Vector2(-0.05, 1.85) * T])
	var sh := PackedVector2Array()
	for q in poly:
		sh.append(q + Vector2(0.3, 0.4) * T)
	c.draw_colored_polygon(sh, Color(0, 0, 0, 0.2))
	c.draw_colored_polygon(poly, TARP)
	for k in range(1, 4):
		var f := float(k) / 4.0
		c.draw_line(poly[0].lerp(poly[1], f), poly[3].lerp(poly[2], f), TARP.darkened(0.25), 2.0)
	c.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), INK, 3.0)
	for q in [poly[0], poly[1], poly[2], poly[3]]:
		c.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), WOOD_D)
		c.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), INK, false, 2.0)
	# floodlight on the north-east corner post
	var lp := lamp_pos(r)
	c.draw_rect(Rect2(lp - Vector2(5, 5) + Vector2(0, 0.2 * T), Vector2(10, 10)), WOOD_D)
	c.draw_rect(Rect2(lp - Vector2(5, 5) + Vector2(0, 0.2 * T), Vector2(10, 10)), INK, false, 2.0)
	c.draw_rect(Rect2(lp - Vector2(10, 7), Vector2(20, 14)), Color(0.25, 0.26, 0.28))
	c.draw_rect(Rect2(lp - Vector2(10, 7), Vector2(20, 14)), INK, false, 2.5)
	c.draw_rect(Rect2(lp - Vector2(6, 3), Vector2(12, 6)), Color(0.85, 0.82, 0.6).lerp(Color(1.0, 0.97, 0.8), night))
