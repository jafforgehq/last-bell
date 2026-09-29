## The parts of a character drawn live each frame so they can move: legs and
## shoes, walkers' reaching arms, and the hands on a weapon. Ported from the
## web version's pawn art; units are tiles, origin at the character's feet.
## Shapes are built once and moved with transforms to keep per-frame work low.
extends RefCounted

const S := preload("res://scripts/render/shapes.gd")

const HEM := 0.13
const FOOT_Y := 0.3
const LW := 0.038
const INK := Color(26.0 / 255.0, 20.0 / 255.0, 15.0 / 255.0, 0.8)
const SHADOW_COL := Color(8.0 / 255.0, 6.0 / 255.0, 4.0 / 255.0, 0.3)

static var SHADOW: PackedVector2Array
static var LEG_S: PackedVector2Array
static var LEG_S_LINE: PackedVector2Array
static var SHOE_S: PackedVector2Array
static var SHOE_S_LINE: PackedVector2Array
static var LEG_E: PackedVector2Array
static var LEG_E_LINE: PackedVector2Array
static var SHOE_E: PackedVector2Array
static var SHOE_E_LINE: PackedVector2Array
static var HAND: PackedVector2Array
static var HAND_LINE: PackedVector2Array
static var GRIP: PackedVector2Array
static var GRIP_LINE: PackedVector2Array
static var _built := false


static func _init_shapes() -> void:
	if _built:
		return
	_built = true
	SHADOW = S.ellipse(0.0, 0.31, 0.3, 0.1, 20)
	LEG_S = S.rrect(-0.07, 0.0, 0.14, 0.215, 0.05, 3)
	LEG_S_LINE = S.closed(LEG_S)
	SHOE_S = S.ellipse(0.0, 0.0, 0.085, 0.052, 14)
	SHOE_S_LINE = S.closed(SHOE_S)
	LEG_E = S.rrect(-0.065, 0.0, 0.13, 0.22, 0.05, 3)
	LEG_E_LINE = S.closed(LEG_E)
	SHOE_E = S.ellipse(0.0, 0.0, 0.1, 0.05, 14)
	SHOE_E_LINE = S.closed(SHOE_E)
	HAND = S.ellipse(0.0, 0.0, 0.062, 0.058, 12)
	HAND_LINE = S.closed(HAND)
	GRIP = S.ellipse(0.0, 0.0, 0.055, 0.055, 12)
	GRIP_LINE = S.closed(GRIP)


## Colours a character needs every frame, parsed once from its look.
static func palette(look: Dictionary) -> Dictionary:
	_init_shapes()
	var pants := Color.html(look.get("pants", "#444444"))
	var shoe := Color.html(look.get("shoes", "#222222"))
	var outer = look.get("outer")
	var style: String = look.get("outerStyle", "")
	var sleeve := Color.html(look.get("top", "#666666"))
	if outer != null and style != "hivis" and style != "vest":
		sleeve = Color.html(outer)
	return {
		"pants": pants,
		"pants_back": pants.darkened(0.18),
		"shoe": shoe,
		"shoe_back": shoe.darkened(0.2),
		"sleeve": sleeve,
		"skin": Color.html(look.get("skin", "#c0a080")),
	}


static func _fill(ci: CanvasItem, at: Vector2, poly: PackedVector2Array, line: PackedVector2Array, col: Color, ink: Color) -> void:
	var xf := Transform2D(0.0, at)
	ci.draw_colored_polygon(xf * poly, col)
	ci.draw_polyline(xf * line, ink, LW, true)


static func shadow(ci: CanvasItem) -> void:
	_init_shapes()
	ci.draw_colored_polygon(SHADOW, SHADOW_COL)


static func legs(ci: CanvasItem, pal: Dictionary, view: String, phase: float, moving: bool, limp: bool, alpha: float = 1.0) -> void:
	var ink := INK
	ink.a *= alpha
	var s := sin(phase) if moving else 0.0
	if view == "E":
		for k: float in [-1.0, 1.0]:
			var amp := 0.04 if (limp and k > 0.0) else 0.1
			var sw := (s * k * amp) if moving else (k * 0.03)
			var lift := (maxf(0.0, cos(phase) * k) * 0.03) if moving else 0.0
			var leg: Color = pal.pants_back if k < 0.0 else pal.pants
			var shoe: Color = pal.shoe_back if k < 0.0 else pal.shoe
			leg.a *= alpha
			shoe.a *= alpha
			_fill(ci, Vector2(sw, HEM - 0.06 - lift), LEG_E, LEG_E_LINE, leg, ink)
			_fill(ci, Vector2(sw + 0.035, FOOT_Y - lift), SHOE_E, SHOE_E_LINE, shoe, ink)
		return
	var pants: Color = pal.pants
	var shoe: Color = pal.shoe
	pants.a *= alpha
	shoe.a *= alpha
	for side: float in [-1.0, 1.0]:
		var amp := 0.35 if (limp and side > 0.0) else 1.0
		var lift := (maxf(0.0, side * s) * 0.055 * amp) if moving else 0.0
		var x := side * 0.105
		_fill(ci, Vector2(x, HEM - 0.06 - lift), LEG_S, LEG_S_LINE, pants, ink)
		_fill(ci, Vector2(x + side * 0.012, FOOT_Y - lift), SHOE_S, SHOE_S_LINE, shoe, ink)


static func _arm(ci: CanvasItem, col: Color, p0: Vector2, ctrl: Vector2, p1: Vector2) -> void:
	var pts := S.quad(p0, ctrl, p1, 6)
	ci.draw_polyline(pts, INK, 0.15, true)
	ci.draw_circle(p0, 0.075, INK)
	ci.draw_circle(p1, 0.075, INK)
	ci.draw_polyline(pts, col, 0.115, true)
	ci.draw_circle(p0, 0.0575, col)
	ci.draw_circle(p1, 0.0575, col)


static func _hand(ci: CanvasItem, skin: Color, x: float, y: float, dirx: float, diry: float) -> void:
	for f: float in [-1.0, 0.0, 1.0]:
		var px := -diry * f * 0.035
		var py := dirx * f * 0.035
		var a := Vector2(x + dirx * 0.03 + px, y + diry * 0.03 + py)
		var b := Vector2(x + dirx * 0.095 + px * 1.2, y + diry * 0.095 + py * 1.2)
		ci.draw_line(a, b, INK, 0.034, true)
		ci.draw_line(a, b - Vector2(dirx, diry) * 0.006, skin, 0.02, true)
	_fill(ci, Vector2(x, y), HAND, HAND_LINE, skin, INK)


## Walkers reach with both arms. layer "back" is drawn before the body,
## "front" after it.
static func arms(ci: CanvasItem, pal: Dictionary, view: String, t: float, attacking: bool, layer: String) -> void:
	var col: Color = pal.sleeve
	var skin: Color = pal.skin
	var claw := 1.0 if attacking else 0.25
	var speed := 7.0 if attacking else 2.2
	if view == "S":
		if layer != "front":
			return
		for s: float in [-1.0, 1.0]:
			var reach := sin(t * speed + s * 1.7) * 0.05 * claw
			var hx := s * 0.2
			var hy := -0.05 + reach
			_arm(ci, col, Vector2(s * 0.27, -0.2), Vector2(s * 0.33, -0.08), Vector2(hx, hy - 0.03))
			_hand(ci, skin, hx, hy + 0.02, 0.0, 1.0)
	elif view == "E":
		var far := layer == "back"
		var reach := sin(t * speed + (1.9 if far else 0.0)) * 0.05 * claw
		var y0 := -0.23 if far else -0.19
		var hx := 0.5 + reach
		var hy := y0 + 0.03 + cos(t * 1.3 + (1.0 if far else 0.0)) * 0.015
		_arm(ci, col, Vector2(0.0, y0), Vector2(0.25, y0 - 0.02), Vector2(hx - 0.05, hy))
		_hand(ci, skin, hx, hy, 1.0, 0.15)
	else:
		if layer != "back":
			return
		for s: float in [-1.0, 1.0]:
			var reach := sin(t * speed + s * 1.7) * 0.04 * claw
			_arm(ci, col, Vector2(s * 0.26, -0.2), Vector2(s * 0.3, -0.32), Vector2(s * 0.2, -0.46 + reach))
			_hand(ci, skin, s * 0.2, -0.5 + reach, 0.0, -1.0)


static func hands(ci: CanvasItem, front, skin: Color) -> void:
	_fill(ci, Vector2(0.0, 0.05), GRIP, GRIP_LINE, skin, INK)
	if front != null:
		_fill(ci, Vector2(float(front), 0.02), GRIP, GRIP_LINE, skin, INK)
