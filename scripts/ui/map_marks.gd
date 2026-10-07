## The shapes of the Map page's marks (One House, UI polish: nothing is told by its colour alone), drawn in one place so that the map and the key under it cannot disagree.
##
##   star / circle / square   a house to claim: the best, a fair one, a poor one (scripts/ui/tier_marks.gd, with the pennants, the arrows at the edge and the minimap)
##   house on gold            your base          brown block   a house looked in
##   blue diamond             someone waits      pale arrow    you (gold: the map's own)      pale triangle   the way in, where the run began
##   ring in a ring           the objective      red triangle  a dead one awake (the minimap's)
##
## Static functions only; `ci` is any CanvasItem and `k` a scale (1 is the map's own size).
extends RefCounted

const BASE_FILL := Color("#f0c24a")
const KNOWN := Color("#7fa6c9")
const DEAD := Color(0.93, 0.25, 0.2, 1.0)
const HOUSE_SEEN := Color("#8a6238")
const HOUSE_EDGE := Color("#d2a94e")
const DARK := Color(0.04, 0.08, 0.07, 1.0)


## The base's house: a roof over a body, dark on the gold block.
static func house(ci: CanvasItem, c: Vector2, r: float, fill: Color = DARK) -> void:
	var roof := PackedVector2Array([c + Vector2(-r, -r * 0.1), c + Vector2(0.0, -r), c + Vector2(r, -r * 0.1)])
	ci.draw_colored_polygon(roof, fill)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.1), Vector2(r * 1.4, r * 1.0)), fill)


## Someone who waits: a blue diamond with a dark rim.
static func known(ci: CanvasItem, c: Vector2, k: float = 1.0) -> void:
	var d := PackedVector2Array([c + Vector2(0, -7) * k, c + Vector2(6, 0) * k, c + Vector2(0, 7) * k, c + Vector2(-6, 0) * k])
	ci.draw_colored_polygon(d, KNOWN)
	var closed := PackedVector2Array(d)
	closed.append(d[0])
	ci.draw_polyline(closed, Color(0, 0, 0, 0.7), 1.5, true)


## You: an arrow on a dark disc.
static func me(ci: CanvasItem, c: Vector2, colour: Color, k: float = 1.0) -> void:
	ci.draw_circle(c, 6.0 * k, Color(0, 0, 0, 0.55))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6) * k, c + Vector2(5, 5) * k, c + Vector2(0, 2) * k, c + Vector2(-5, 5) * k]), colour)


## The objective's place: two rings.
static func goal(ci: CanvasItem, c: Vector2, colour: Color, k: float = 1.0) -> void:
	ci.draw_arc(c, 8.0 * k, 0.0, TAU, 24, Color(colour, 0.9), 2.0, true)
	ci.draw_arc(c, 12.0 * k, 0.0, TAU, 24, Color(colour, 0.4), 1.5, true)


## The way in (where the run began): a plain triangle turned to the way the run went (`angle`, 0 is east).
static func entry(ci: CanvasItem, at: Vector2, angle: float, colour: Color, k: float = 1.0) -> void:
	var f := Vector2.from_angle(angle)
	var s := Vector2(-f.y, f.x)
	var tri := PackedVector2Array([at + f * 7.0 * k, at - f * 4.0 * k + s * 5.0 * k, at - f * 4.0 * k - s * 5.0 * k])
	ci.draw_colored_polygon(tri, colour)
	var rim := PackedVector2Array(tri)
	rim.append(tri[0])
	ci.draw_polyline(rim, Color(0, 0, 0, 0.7), 1.5, true)


## A dead one that is awake (the minimap's): a red triangle with a pale rim.
static func dead(ci: CanvasItem, c: Vector2, r: float = 4.5) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)])
	ci.draw_colored_polygon(pts, DEAD)
	var line := PackedVector2Array(pts)
	line.append(pts[0])
	ci.draw_polyline(line, Color(0.97, 0.96, 0.9, 0.95), 1.3, true)


## A house looked in: a brown block with a gold edge. (A wide one, so that it is not mistaken for a poor house's square.)
static func seen(ci: CanvasItem, c: Vector2) -> void:
	var r := Rect2(c - Vector2(8.0, 5.0), Vector2(16.0, 10.0))
	ci.draw_rect(r, HOUSE_SEEN)
	ci.draw_rect(r, HOUSE_EDGE, false, 1.0)


## The base: a gold block with its house on it.
static func base(ci: CanvasItem, c: Vector2) -> void:
	var r := Rect2(c - Vector2(8.0, 5.0), Vector2(16.0, 10.0))
	ci.draw_rect(r, BASE_FILL)
	ci.draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
	house(ci, c + Vector2(0.0, 0.5), 3.8)
