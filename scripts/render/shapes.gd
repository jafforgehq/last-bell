## Small vector-drawing helpers so the ported canvas code reads the same:
## rounded rectangles, ellipses, thick curves with round caps, outlines.
## All work in whatever units the canvas item's current transform uses.
extends RefCounted

const INK := Color(26.0 / 255.0, 20.0 / 255.0, 15.0 / 255.0, 0.8)
const LW := 0.038


static func rrect(x: float, y: float, w: float, h: float, r: float, seg: int = 4) -> PackedVector2Array:
	r = minf(r, minf(w, h) * 0.5)
	var pts := PackedVector2Array()
	var corners := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	var starts := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for c in 4:
		for i in seg + 1:
			var a: float = starts[c] + (PI / 2.0) * float(i) / float(seg)
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * r)
	return pts


static func ellipse(cx: float, cy: float, rx: float, ry: float, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


static func fill_ink(ci: CanvasItem, pts: PackedVector2Array, color: Color, lw: float = LW, ink: Color = INK) -> void:
	ci.draw_colored_polygon(pts, color)
	if lw > 0.0:
		ci.draw_polyline(closed(pts), ink, lw, true)


static func quad(p0: Vector2, c: Vector2, p1: Vector2, n: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(p0 * u * u + c * 2.0 * u * t + p1 * t * t)
	return pts


static func cubic(p0: Vector2, c0: Vector2, c1: Vector2, p1: Vector2, n: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(p0 * u * u * u + c0 * 3.0 * u * u * t + c1 * 3.0 * u * t * t + p1 * t * t * t)
	return pts


## A stroke with round caps, like canvas lineCap = 'round'.
static func stroke(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	ci.draw_polyline(pts, color, width, true)
	ci.draw_circle(pts[0], width * 0.5, color)
	ci.draw_circle(pts[pts.size() - 1], width * 0.5, color)
