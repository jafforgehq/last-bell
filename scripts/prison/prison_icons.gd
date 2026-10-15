## EXPERIMENT (prison UI round 2): tiny icons drawn in code (no image files), shared by the top bar, the objective tracker and the tags over the crew's heads.
## `draw(c, id, centre, size, colour)` paints into any CanvasItem (a Control's draw callback, or the HUD layer's tags control). Everything is a few primitives in a box of `size` pixels, one flat colour
## plus a darker edge so the icon reads on grass, concrete and the dark plate. Unknown ids draw a dot.
extends RefCounted

const EDGE := Color(0.03, 0.05, 0.04, 0.85)


static func _poly(c: CanvasItem, pts: Array, col: Color) -> void:
	var a := PackedVector2Array(pts)
	c.draw_colored_polygon(a, col)


static func draw(c: CanvasItem, id: String, p: Vector2, s: float, col: Color) -> void:
	var r := s * 0.5
	var dk := col.darkened(0.55)
	var w := maxf(1.5, s / 9.0)
	match id:
		"food":    # an apple: round body, leaf
			c.draw_circle(p + Vector2(0, r * 0.15), r * 0.72, col)
			_poly(c, [p + Vector2(0.05, -r * 0.5) * 1.0, p + Vector2(r * 0.55, -r * 0.95), p + Vector2(r * 0.6, -r * 0.45)], dk.lightened(0.5))
			c.draw_arc(p + Vector2(0, r * 0.15), r * 0.72, 0, TAU, 16, EDGE, 1.0, true)
		"water":    # a drop
			_poly(c, [p + Vector2(0, -r), p + Vector2(r * 0.62, r * 0.15), p + Vector2(-r * 0.62, r * 0.15)], col)
			c.draw_circle(p + Vector2(0, r * 0.3), r * 0.62, col)
			c.draw_circle(p + Vector2(-r * 0.2, r * 0.2), r * 0.16, Color(1, 1, 1, 0.55))
		"ammo":    # three rounds
			for i in 3:
				var x := (float(i) - 1.0) * r * 0.62
				c.draw_rect(Rect2(p + Vector2(x - r * 0.2, -r * 0.2), Vector2(r * 0.4, r * 1.1)), col)
				c.draw_circle(p + Vector2(x, -r * 0.2), r * 0.2, col.lightened(0.25))
				c.draw_rect(Rect2(p + Vector2(x - r * 0.2, r * 0.7), Vector2(r * 0.4, r * 0.2)), dk)
		"meds":    # a first-aid cross
			c.draw_rect(Rect2(p - Vector2(r * 0.85, r * 0.85), Vector2(r * 1.7, r * 1.7)), Color(0.93, 0.93, 0.9))
			c.draw_rect(Rect2(p - Vector2(r * 0.22, r * 0.62), Vector2(r * 0.44, r * 1.24)), col)
			c.draw_rect(Rect2(p - Vector2(r * 0.62, r * 0.22), Vector2(r * 1.24, r * 0.44)), col)
		"scrap":    # a gear
			for i in 8:
				var a := TAU * float(i) / 8.0
				c.draw_line(p + Vector2.from_angle(a) * r * 0.5, p + Vector2.from_angle(a) * r * 0.95, col, w * 1.3)
			c.draw_circle(p, r * 0.62, col)
			c.draw_circle(p, r * 0.24, EDGE)
		"parts":    # a chip with legs
			for i in 3:
				var o := (float(i) - 1.0) * r * 0.5
				c.draw_line(p + Vector2(o, -r), p + Vector2(o, r), col.darkened(0.2), w * 0.8)
				c.draw_line(p + Vector2(-r, o), p + Vector2(r, o), col.darkened(0.2), w * 0.8)
			c.draw_rect(Rect2(p - Vector2(r * 0.65, r * 0.65), Vector2(r * 1.3, r * 1.3)), col)
			c.draw_rect(Rect2(p - Vector2(r * 0.3, r * 0.3), Vector2(r * 0.6, r * 0.6)), dk)
		"fuel":    # a jerry can
			c.draw_rect(Rect2(p + Vector2(-r * 0.7, -r * 0.55), Vector2(r * 1.4, r * 1.5)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.15, -r * 0.95), Vector2(r * 0.75, r * 0.45)), col.darkened(0.2))
			c.draw_line(p + Vector2(-r * 0.45, -r * 0.1), p + Vector2(r * 0.45, r * 0.65), dk, w)
			c.draw_line(p + Vector2(r * 0.45, -r * 0.1), p + Vector2(-r * 0.45, r * 0.65), dk, w)
		"sun":
			c.draw_circle(p, r * 0.5, col)
			for i in 8:
				var a2 := TAU * float(i) / 8.0
				c.draw_line(p + Vector2.from_angle(a2) * r * 0.72, p + Vector2.from_angle(a2) * r * 0.98, col, w)
		"moon":
			c.draw_circle(p, r * 0.78, col)
			c.draw_circle(p + Vector2(r * 0.42, -r * 0.22), r * 0.68, Color(0.05, 0.08, 0.07, 1.0))
		"people":
			c.draw_circle(p + Vector2(0, -r * 0.4), r * 0.36, col)
			c.draw_arc(p + Vector2(0, r * 0.95), r * 0.8, PI * 1.12, PI * 1.88, 12, col, r * 0.55, true)
		"face_good", "face_mid", "face_bad":
			c.draw_circle(p, r * 0.9, col)
			c.draw_circle(p + Vector2(-r * 0.32, -r * 0.2), r * 0.12, EDGE)
			c.draw_circle(p + Vector2(r * 0.32, -r * 0.2), r * 0.12, EDGE)
			if id == "face_good":
				c.draw_arc(p + Vector2(0, r * 0.05), r * 0.46, 0.25, PI - 0.25, 10, EDGE, w * 0.8, true)
			elif id == "face_bad":
				c.draw_arc(p + Vector2(0, r * 0.7), r * 0.4, PI + 0.3, TAU - 0.3, 10, EDGE, w * 0.8, true)
			else:
				c.draw_line(p + Vector2(-r * 0.36, r * 0.38), p + Vector2(r * 0.36, r * 0.38), EDGE, w * 0.8)
		"star":
			var pts: Array = []
			for i in 10:
				var rr := r if i % 2 == 0 else r * 0.42
				pts.append(p + Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 10.0) * rr)
			_poly(c, pts, col)
		"bell":
			c.draw_arc(p + Vector2(0, -r * 0.05), r * 0.62, PI, TAU, 12, col, r * 0.5, true)
			c.draw_rect(Rect2(p + Vector2(-r * 0.8, -r * 0.05), Vector2(r * 1.6, r * 0.55)), col)
			c.draw_circle(p + Vector2(0, r * 0.8), r * 0.2, col)
		"fence":
			for i in 4:
				var x2 := (float(i) - 1.5) * r * 0.55
				c.draw_line(p + Vector2(x2, -r * 0.8), p + Vector2(x2, r * 0.8), col, w)
			c.draw_line(p + Vector2(-r, -r * 0.3), p + Vector2(r, -r * 0.3), col, w * 0.8)
			c.draw_line(p + Vector2(-r, r * 0.4), p + Vector2(r, r * 0.4), col, w * 0.8)
		"zones":
			for i in 4:
				c.draw_rect(Rect2(p + Vector2(float(i % 2) * r * 0.95 - r * 0.9, float(i / 2) * r * 0.95 - r * 0.9), Vector2(r * 0.85, r * 0.85)), col if i != 3 else col.darkened(0.45))
		"heart":
			c.draw_circle(p + Vector2(-r * 0.38, -r * 0.2), r * 0.46, col)
			c.draw_circle(p + Vector2(r * 0.38, -r * 0.2), r * 0.46, col)
			_poly(c, [p + Vector2(-r * 0.82, -r * 0.0), p + Vector2(r * 0.82, -r * 0.0), p + Vector2(0, r * 0.9)], col)
		"binoculars", "gate":
			for sx in [-1.0, 1.0]:
				c.draw_circle(p + Vector2(sx * r * 0.45, r * 0.2), r * 0.42, col)
				c.draw_circle(p + Vector2(sx * r * 0.45, r * 0.2), r * 0.18, EDGE)
				c.draw_rect(Rect2(p + Vector2(sx * r * 0.45 - r * 0.2, -r * 0.65), Vector2(r * 0.4, r * 0.75)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.15, -r * 0.1), Vector2(r * 0.3, r * 0.4)), col)
		"shield", "guard":
			_poly(c, [p + Vector2(-r * 0.72, -r * 0.8), p + Vector2(r * 0.72, -r * 0.8), p + Vector2(r * 0.72, r * 0.1), p + Vector2(0, r), p + Vector2(-r * 0.72, r * 0.1)], col)
			c.draw_line(p + Vector2(0, -r * 0.55), p + Vector2(0, r * 0.45), EDGE, w * 0.8)
		"leaf", "farm":
			c.draw_circle(p + Vector2(0, 0), r * 0.7, col)
			_poly(c, [p + Vector2(-r * 0.7, 0), p + Vector2(0, -r * 0.7), p + Vector2(r * 0.7, 0), p + Vector2(0, r * 0.7)], col)
			c.draw_line(p + Vector2(-r * 0.6, r * 0.7), p + Vector2(r * 0.5, -r * 0.5), EDGE, w * 0.8)
		"pot", "cook":
			c.draw_rect(Rect2(p + Vector2(-r * 0.75, -r * 0.2), Vector2(r * 1.5, r * 0.95)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.9, -r * 0.35), Vector2(r * 1.8, r * 0.2)), col.lightened(0.15))
			for i in 2:
				c.draw_arc(p + Vector2((float(i) - 0.5) * r * 0.7, -r * 0.7), r * 0.2, PI * 0.5, PI * 2.0, 8, Color(1, 1, 1, 0.6), w * 0.7, true)
		"cross", "nurse":
			c.draw_rect(Rect2(p - Vector2(r * 0.3, r * 0.9), Vector2(r * 0.6, r * 1.8)), col)
			c.draw_rect(Rect2(p - Vector2(r * 0.9, r * 0.3), Vector2(r * 1.8, r * 0.6)), col)
		"wrench", "repair":
			c.draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.4, -r * 0.4), col, w * 1.6)
			c.draw_circle(p + Vector2(r * 0.5, -r * 0.5), r * 0.45, col)
			c.draw_circle(p + Vector2(r * 0.68, -r * 0.68), r * 0.2, EDGE)
		"broom", "clean":
			c.draw_line(p + Vector2(r * 0.7, -r * 0.9), p + Vector2(-r * 0.2, r * 0.2), col.darkened(0.2), w * 1.2)
			_poly(c, [p + Vector2(-r * 0.7, r * 0.1), p + Vector2(r * 0.3, r * 0.5), p + Vector2(0, r * 0.95), p + Vector2(-r * 0.95, r * 0.8)], col)
		"rest", "zzz":
			for i in 2:
				var q := p + Vector2(float(i) * r * 0.45 - r * 0.45, float(1 - i) * r * 0.5 - r * 0.15)
				var k := r * (0.5 - 0.15 * float(i))
				c.draw_polyline(PackedVector2Array([q + Vector2(-k, -k), q + Vector2(k, -k), q + Vector2(-k, k), q + Vector2(k, k)]), col, w, true)
		"hammer", "build":
			c.draw_line(p + Vector2(-r * 0.7, r * 0.8), p + Vector2(r * 0.25, -r * 0.2), col.darkened(0.25), w * 1.4)
			c.draw_rect(Rect2(p + Vector2(-r * 0.15, -r * 0.85), Vector2(r * 1.05, r * 0.55)), col)
		"boot", "patrol":
			_poly(c, [p + Vector2(-r * 0.5, -r * 0.9), p + Vector2(r * 0.1, -r * 0.9), p + Vector2(r * 0.15, r * 0.1), p + Vector2(r * 0.95, r * 0.35), p + Vector2(r * 0.95, r * 0.85), p + Vector2(-r * 0.5, r * 0.85)], col)
		"fork", "eat":
			for i in 3:
				c.draw_line(p + Vector2((float(i) - 1.0) * r * 0.35, -r * 0.9), p + Vector2((float(i) - 1.0) * r * 0.35, -r * 0.1), col, w * 0.7)
			c.draw_line(p + Vector2(-r * 0.35, -r * 0.1), p + Vector2(r * 0.35, -r * 0.1), col, w)
			c.draw_line(p + Vector2(0, -r * 0.1), p + Vector2(0, r * 0.95), col, w * 1.2)
		"crate", "haul":
			c.draw_rect(Rect2(p - Vector2(r * 0.85, r * 0.75), Vector2(r * 1.7, r * 1.5)), col)
			c.draw_rect(Rect2(p - Vector2(r * 0.85, r * 0.75), Vector2(r * 1.7, r * 1.5)), EDGE, false, 1.5)
			c.draw_line(p + Vector2(-r * 0.85, -r * 0.1), p + Vector2(r * 0.85, -r * 0.1), EDGE, 1.5)
		"clock":
			c.draw_arc(p, r * 0.82, 0, TAU, 16, col, w, true)
			c.draw_line(p, p + Vector2(0, -r * 0.55), col, w)
			c.draw_line(p, p + Vector2(r * 0.4, r * 0.2), col, w)
		"play":
			c.draw_circle(p, r * 0.7, col)
			c.draw_arc(p, r * 0.7, 0.3, 2.6, 8, Color(1, 1, 1, 0.8), 1.5, true)
		"up":
			_poly(c, [p + Vector2(0, -r * 0.8), p + Vector2(r * 0.8, r * 0.6), p + Vector2(-r * 0.8, r * 0.6)], col)
		"down":
			_poly(c, [p + Vector2(0, r * 0.8), p + Vector2(r * 0.8, -r * 0.6), p + Vector2(-r * 0.8, -r * 0.6)], col)
		"flat":
			c.draw_rect(Rect2(p - Vector2(r * 0.8, r * 0.18), Vector2(r * 1.6, r * 0.36)), col)
		"exit":
			c.draw_rect(Rect2(p - Vector2(r * 0.55, r * 0.9), Vector2(r * 1.1, r * 1.8)), col, false, w)
			c.draw_line(p + Vector2(-r * 0.9, 0), p + Vector2(r * 0.3, 0), col, w)
			_poly(c, [p + Vector2(r * 0.3, -r * 0.4), p + Vector2(r * 0.85, 0), p + Vector2(r * 0.3, r * 0.4)], col)
		"box":
			c.draw_rect(Rect2(p - Vector2(r * 0.8, r * 0.8), Vector2(r * 1.6, r * 1.6)), col, false, w * 0.8)
		"boxcheck":
			c.draw_rect(Rect2(p - Vector2(r * 0.8, r * 0.8), Vector2(r * 1.6, r * 1.6)), col, false, w * 0.8)
			c.draw_polyline(PackedVector2Array([p + Vector2(-r * 0.45, 0), p + Vector2(-r * 0.1, r * 0.4), p + Vector2(r * 0.5, -r * 0.45)]), col, w * 1.1, true)
		"pack":
			c.draw_rect(Rect2(p + Vector2(-r * 0.7, -r * 0.5), Vector2(r * 1.4, r * 1.45)), col)
			c.draw_arc(p + Vector2(0, -r * 0.5), r * 0.45, PI, TAU, 8, col, w, true)
			c.draw_rect(Rect2(p + Vector2(-r * 0.4, r * 0.15), Vector2(r * 0.8, r * 0.4)), dk)
		"target":
			c.draw_arc(p, r * 0.85, 0, TAU, 16, col, w, true)
			c.draw_arc(p, r * 0.4, 0, TAU, 12, col, w, true)
			c.draw_circle(p, r * 0.12, col)
		_:
			c.draw_circle(p, r * 0.4, col)


const SKINS := [Color("#f0c8a0"), Color("#d9a577"), Color("#b87f56"), Color("#8a5a3c"), Color("#5e3b2a")]
const HAIRS := [Color("#1f1a17"), Color("#4a3020"), Color("#7a4a2a"), Color("#b8863a"), Color("#8a8a8a"), Color("#a8483c")]
const CLOTHES := [Color("#4a6a8a"), Color("#7a8a4a"), Color("#a8483c"), Color("#6a5a44"), Color("#555a50"), Color("#8a6aa0"), Color("#c9b25a")]


## A small bust for a person, drawn flat with a dark outline into `r` of any CanvasItem. Skin, hair and clothes come from the id, so a person looks the same everywhere.
static func portrait(c: CanvasItem, id: String, r: Rect2) -> void:
	var h := absi(id.hash())
	var skin: Color = SKINS[h % SKINS.size()]
	var hair: Color = HAIRS[(h / 7) % HAIRS.size()]
	var top: Color = CLOTHES[(h / 53) % CLOTHES.size()]
	var s := minf(r.size.x, r.size.y)
	var ctr := r.position + r.size * 0.5
	var u := s / 20.0
	c.draw_rect(r, Color(0.12, 0.15, 0.16, 0.9))
	# shoulders
	var sh := PackedVector2Array([ctr + Vector2(-8, 10) * u, ctr + Vector2(-7, 5.5) * u, ctr + Vector2(-3, 4) * u, ctr + Vector2(3, 4) * u, ctr + Vector2(7, 5.5) * u, ctr + Vector2(8, 10) * u])
	c.draw_colored_polygon(sh, top)
	c.draw_polyline(sh, EDGE, maxf(1.0, u * 0.7))
	c.draw_rect(Rect2(ctr + Vector2(-1.8, 2.2) * u, Vector2(3.6, 3.0) * u), skin.darkened(0.15))
	# head and hair
	var hc := ctr + Vector2(0, -2.2) * u
	c.draw_circle(hc, 5.6 * u, EDGE)
	c.draw_circle(hc, 4.8 * u, skin)
	if (h / 11) % 3 == 0:    # a short crop
		c.draw_arc(hc, 4.6 * u, PI * 1.05, PI * 1.95, 10, hair, 2.4 * u, true)
	else:
		c.draw_colored_polygon(PackedVector2Array([hc + Vector2(-5, 0.5) * u, hc + Vector2(-4.4, -3.8) * u, hc + Vector2(0, -5.6) * u, hc + Vector2(4.4, -3.8) * u, hc + Vector2(5, 0.5) * u, hc + Vector2(3.4, -1.6) * u, hc + Vector2(-3.4, -1.6) * u]), hair)
		if (h / 11) % 3 == 1:    # long hair falls past the ears
			c.draw_rect(Rect2(hc + Vector2(-5.2, -1.0) * u, Vector2(1.6, 5.0) * u), hair)
			c.draw_rect(Rect2(hc + Vector2(3.6, -1.0) * u, Vector2(1.6, 5.0) * u), hair)
	c.draw_circle(hc + Vector2(-1.9, 0.4) * u, 0.55 * u, EDGE)
	c.draw_circle(hc + Vector2(1.9, 0.4) * u, 0.55 * u, EDGE)
	c.draw_rect(r, EDGE, false, 1.0)


## A Control with the person's bust in it, `px` square.
static func portrait_box(id: String, px: float = 28.0) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(px, px)
	b.draw.connect(func() -> void: portrait(b, id, Rect2(Vector2.ZERO, b.size)))
	return b


## COLOUR-BLIND MARKERS: ally = triangle, dead = X, loot = diamond, drawn with a dark outline. Callers use them in place of a plain dot only when `Access.markers()` is on.
static func mark(c: CanvasItem, shape: String, p: Vector2, r: float, col: Color) -> void:
	match shape:
		"ally":
			var t := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.95, r * 0.8), p + Vector2(-r * 0.95, r * 0.8)])
			c.draw_colored_polygon(t, col)
			c.draw_polyline(PackedVector2Array([t[0], t[1], t[2], t[0]]), EDGE, 1.0)
		"dead":
			c.draw_line(p + Vector2(-r, -r), p + Vector2(r, r), EDGE, 3.0)
			c.draw_line(p + Vector2(-r, r), p + Vector2(r, -r), EDGE, 3.0)
			c.draw_line(p + Vector2(-r, -r), p + Vector2(r, r), col, 1.6)
			c.draw_line(p + Vector2(-r, r), p + Vector2(r, -r), col, 1.6)
		_:    # loot
			var d := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			c.draw_colored_polygon(d, col)
			c.draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), EDGE, 1.0)
