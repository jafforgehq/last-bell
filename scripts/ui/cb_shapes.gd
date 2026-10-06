## The shapes of "Colour-blind markers" (Settings; `Access.markers()`): small marks drawn beside, or instead of, a colour, so that nothing is told by its colour alone. A mark is a shape of
## its own with a pale rim (so it reads on any ground) and the colour it always had:
##
##   triangle  a warning (hurt, hungry, refusing; a pennant's flag)       diamond  danger (bleeding, feverish, down, starving; someone known of)
##   square    the dead awake, a house looked in                         circle   fine, or a person (stable, ready, a survivor)
##   plus      good, holds, done, a house to claim                       minus    short, does not hold
##   cross     locked, lost, fallen                                      check    done
##
## `mark(ci, kind, centre, radius, colour)` draws one on any CanvasItem; `Mark` is a Control of the same, for a layout (the Build page's state beside its word). Pure drawing: nothing here
## reads the game.
extends RefCounted

const RIM := Color(0.97, 0.96, 0.9, 0.95)
const HALO := Color(0.02, 0.04, 0.035, 0.85)


## The outline of a filled shape of `kind` ("triangle", "diamond", "square") of radius `r` round `c`.
static func outline(kind: String, c: Vector2, r: float) -> PackedVector2Array:
	match kind:
		"triangle":
			return PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 1.0, r * 0.8), c + Vector2(-r * 1.0, r * 0.8)])
		"diamond":
			return PackedVector2Array([c + Vector2(0, -r * 1.15), c + Vector2(r * 0.95, 0), c + Vector2(0, r * 1.15), c + Vector2(-r * 0.95, 0)])
		"square":
			return PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.85), c + Vector2(r * 0.85, -r * 0.85), c + Vector2(r * 0.85, r * 0.85), c + Vector2(-r * 0.85, r * 0.85)])
	return PackedVector2Array()


## Draws one mark of `kind` in `colour` on `ci`, `r` the radius in pixels (3 is small, 5 is a clear mark).
static func mark(ci: CanvasItem, kind: String, c: Vector2, r: float, colour: Color, rim: Color = RIM) -> void:
	match kind:
		"triangle", "diamond", "square":
			var pts := outline(kind, c, r)
			var line := PackedVector2Array(pts)
			line.append(pts[0])
			ci.draw_colored_polygon(pts, colour)
			ci.draw_polyline(line, rim, maxf(1.0, r * 0.28), true)
		"circle":
			ci.draw_circle(c, r, colour)
			ci.draw_arc(c, r, 0.0, TAU, 20, rim, maxf(1.0, r * 0.28), true)
		"plus":
			_glyph(ci, [[Vector2(-1, 0), Vector2(1, 0)], [Vector2(0, -1), Vector2(0, 1)]], c, r, colour)
		"minus":
			_glyph(ci, [[Vector2(-1, 0), Vector2(1, 0)]], c, r, colour)
		"cross":
			_glyph(ci, [[Vector2(-0.8, -0.8), Vector2(0.8, 0.8)], [Vector2(-0.8, 0.8), Vector2(0.8, -0.8)]], c, r, colour)
		"check":
			_glyph(ci, [[Vector2(-0.9, 0.05), Vector2(-0.3, 0.7)], [Vector2(-0.3, 0.7), Vector2(0.95, -0.75)]], c, r, colour)


## A sign drawn as lines: a dark halo under the colour, so that it reads on a pale or a busy ground.
static func _glyph(ci: CanvasItem, strokes: Array, c: Vector2, r: float, colour: Color) -> void:
	var w := maxf(1.6, r * 0.5)
	for s in strokes:
		ci.draw_line(c + (s[0] as Vector2) * r, c + (s[1] as Vector2) * r, HALO, w + 2.0, true)
	for s in strokes:
		ci.draw_line(c + (s[0] as Vector2) * r, c + (s[1] as Vector2) * r, colour, w, true)


## A Control that is one mark, for a layout.
class Mark:
	extends Control
	var kind := "circle"
	var colour := Color.WHITE
	var radius := 5.0

	func _init(shape: String = "circle", tint: Color = Color.WHITE, r: float = 5.0) -> void:
		kind = shape
		colour = tint
		radius = r
		custom_minimum_size = Vector2(r * 2.0 + 4.0, r * 2.0 + 4.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_kind(shape: String, tint: Color) -> void:
		if shape != kind or tint != colour:
			kind = shape
			colour = tint
			queue_redraw()

	func _draw() -> void:
		mark_on(self, kind, size * 0.5, radius, colour)

	static func mark_on(ci: CanvasItem, shape: String, c: Vector2, r: float, tint: Color) -> void:
		var script := load("res://scripts/ui/cb_shapes.gd")
		script.mark(ci, shape, c, r, tint)
