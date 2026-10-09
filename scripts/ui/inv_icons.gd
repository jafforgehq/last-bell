## The pictures of the inventory (INV-UI): every item, the pack and the equipment drawn in code, in the game's own flat outlined style (a dark outline, one flat colour, one pale highlight),
## so that no file is needed and each kind is told by its SHAPE as well as its colour (a can is round and short, a bottle tall with a cap, a bandage a roll, a medkit a case with a cross, a box
## of shells a box with red tips, loose shells three red tubes, a jug is a body with a handle, a ration pack a flat pack with a notched top). They read at 40 px and at 48 px.
##
## `draw_item(ci, id, rect, rot, cell)` paints the item into `rect` (its footprint in pixels, already turned by `rot`: a turned item is the picture turned a quarter). Drawing is done in the
## item's own unit of one cell (`cell` pixels), the origin at the footprint's top left, whatever the size. Pure drawing: nothing here reads the game.
extends RefCounted

const InvApi := preload("res://scripts/ui/inv_api.gd")

## The items that have a picture of their own (`paint`); any other is drawn as a box with a question mark, and a test says so when items.json has one more.
const KNOWN := ["shells", "shell_box", "canned_food", "ration_pack", "water_bottle", "water_jug", "bandage", "medkit"]

const OUT := Color("#0e1a15")
const RED := Color("#c2453a")
const RED_DARK := Color("#8f2f27")
const BRASS := Color("#d2a94e")
const BRASS_DARK := Color("#a07f2f")
const PAPER := Color("#d8b46a")
const TIN := Color("#aab3ac")
const TIN_LIGHT := Color("#d3dad3")
const ORANGE := Color("#dc7a2c")
const CREAM := Color("#ece4cd")
const CREAM_DARK := Color("#c9bf9f")
const OLIVE := Color("#718046")
const OLIVE_DARK := Color("#4d5a2c")
const BLUE := Color("#4f9fd0")
const BLUE_DARK := Color("#37789f")
const BLUE_PALE := Color("#cfe6f3")
const WHITE := Color("#f0ece0")
const GREY := Color("#7d857e")
const STRIP := Color("#d9a779")
const WOOD := Color("#8a6238")
const WOOD_DARK := Color("#56391f")
const STEEL := Color("#5c6660")

## The colour a store is told by (a faint wash behind its items, the stores panel's rows).
const RES_COLOR := {"ammo": Color("#d2a94e"), "food": Color("#e09040"), "water": Color("#4f9fd0"), "meds": Color("#e0584a"), "scrap": Color("#9aa39c")}


static func res_color(res: String) -> Color:
	return RES_COLOR.get(res, Color("#b3a57f"))


## The stroke of an outline at this cell size.
static func lw(k: float) -> float:
	return maxf(1.5, k / 30.0)


## `id` painted in `rect` (the footprint on screen, turned by `rot`), at `cell` pixels a cell.
static func draw_item(ci: CanvasItem, id: String, rect: Rect2, rot: int, cell: float) -> void:
	var d: Dictionary = InvApi.item(id)
	var ch := float(d.h) * cell
	if rot == 1:
		ci.draw_set_transform(rect.position + Vector2(ch, 0.0), PI / 2.0, Vector2.ONE)
	else:
		ci.draw_set_transform(rect.position, 0.0, Vector2.ONE)
	paint(ci, id, cell)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The picture in the item's own orientation, the origin at its corner, in units of `k` pixels.
static func paint(ci: CanvasItem, id: String, k: float) -> void:
	match id:
		"shells":
			_shells(ci, k)
		"shell_box":
			_shell_box(ci, k)
		"canned_food":
			_can(ci, k)
		"ration_pack":
			_ration(ci, k)
		"water_bottle":
			_bottle(ci, k)
		"water_jug":
			_jug(ci, k)
		"bandage":
			_bandage(ci, k)
		"medkit":
			_medkit(ci, k)
		_:
			_unknown(ci, k)


# ------------------------------------------------------------------------------ the pieces --

static func _rect(ci: CanvasItem, k: float, x0: float, y0: float, x1: float, y1: float, fill: Color) -> void:
	var r := Rect2(Vector2(x0, y0) * k, Vector2(x1 - x0, y1 - y0) * k)
	ci.draw_rect(r, fill)
	ci.draw_rect(r, OUT, false, lw(k))


static func _poly(ci: CanvasItem, k: float, pts: Array, fill: Color) -> void:
	var p := PackedVector2Array()
	for q in pts:
		p.append((q as Vector2) * k)
	ci.draw_colored_polygon(p, fill)
	var l := PackedVector2Array(p)
	l.append(p[0])
	ci.draw_polyline(l, OUT, lw(k), true)


## A rectangle with its corners cut off by `r` (cell units).
static func _rrect(ci: CanvasItem, k: float, x0: float, y0: float, x1: float, y1: float, r: float, fill: Color) -> void:
	_poly(ci, k, [Vector2(x0 + r, y0), Vector2(x1 - r, y0), Vector2(x1, y0 + r), Vector2(x1, y1 - r), Vector2(x1 - r, y1), Vector2(x0 + r, y1), Vector2(x0, y1 - r), Vector2(x0, y0 + r)], fill)


static func _disc(ci: CanvasItem, k: float, cx: float, cy: float, r: float, fill: Color) -> void:
	ci.draw_circle(Vector2(cx, cy) * k, r * k, fill)
	ci.draw_arc(Vector2(cx, cy) * k, r * k, 0.0, TAU, 28, OUT, lw(k), true)


static func _line(ci: CanvasItem, k: float, a: Vector2, b: Vector2, col: Color, w: float = 0.05) -> void:
	ci.draw_line(a * k, b * k, col, maxf(1.0, w * k), true)


## `pts` (cell units, round the origin) turned by `a` radians and put round `c`.
static func _turned(pts: Array, a: float, c: Vector2) -> Array:
	var out: Array = []
	for p in pts:
		out.append(c + (p as Vector2).rotated(a))
	return out


static func _ellipse(ci: CanvasItem, k: float, c: Vector2, rx: float, ry: float, fill: Color) -> void:
	var pts: Array = []
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_poly(ci, k, pts, fill)


# ---------------------------------------------------------------------------------- items --

static func _shells(ci: CanvasItem, k: float) -> void:
	for i in 3:
		var x := 0.2 + 0.2 * float(i)
		var top := 0.2 if i == 1 else 0.28
		_rect(ci, k, x, top, x + 0.17, 0.66, RED)
		_rect(ci, k, x, 0.66, x + 0.17, 0.8, BRASS)
		_line(ci, k, Vector2(x + 0.03, top + 0.04), Vector2(x + 0.03, 0.6), Color(1, 1, 1, 0.35), 0.035)


static func _shell_box(ci: CanvasItem, k: float) -> void:
	_disc(ci, k, 0.3, 0.33, 0.07, RED)
	_disc(ci, k, 0.5, 0.29, 0.07, RED)
	_disc(ci, k, 0.7, 0.33, 0.07, RED)
	_rect(ci, k, 0.14, 0.38, 0.86, 0.84, PAPER)
	_rect(ci, k, 0.14, 0.38, 0.86, 0.5, BRASS_DARK)
	_rect(ci, k, 0.3, 0.6, 0.7, 0.74, RED)


static func _can(ci: CanvasItem, k: float) -> void:
	_rect(ci, k, 0.25, 0.3, 0.75, 0.8, TIN)
	_rect(ci, k, 0.25, 0.43, 0.75, 0.67, ORANGE)
	_ellipse(ci, k, Vector2(0.5, 0.3), 0.25, 0.065, TIN_LIGHT)
	_ellipse(ci, k, Vector2(0.5, 0.8), 0.25, 0.05, TIN)
	_disc(ci, k, 0.5, 0.55, 0.07, CREAM)


static func _ration(ci: CanvasItem, k: float) -> void:
	_poly(ci, k, [Vector2(0.2, 0.36), Vector2(0.28, 0.26), Vector2(0.36, 0.36), Vector2(0.44, 0.26), Vector2(0.52, 0.36), Vector2(0.6, 0.26), Vector2(0.68, 0.36), Vector2(0.76, 0.26), Vector2(0.8, 0.36), Vector2(0.8, 1.72), Vector2(0.2, 1.72)], OLIVE)
	_rect(ci, k, 0.3, 0.76, 0.7, 1.36, CREAM)
	_line(ci, k, Vector2(0.42, 0.9), Vector2(0.42, 1.24), OLIVE_DARK, 0.06)
	_line(ci, k, Vector2(0.58, 0.9), Vector2(0.58, 1.24), OLIVE_DARK, 0.06)
	_line(ci, k, Vector2(0.38, 0.9), Vector2(0.62, 0.9), OLIVE_DARK, 0.05)
	_rect(ci, k, 0.2, 1.5, 0.8, 1.62, OLIVE_DARK)


static func _bottle(ci: CanvasItem, k: float) -> void:
	_rect(ci, k, 0.4, 0.1, 0.6, 0.23, BLUE_PALE)
	_poly(ci, k, [Vector2(0.42, 0.23), Vector2(0.58, 0.23), Vector2(0.62, 0.42), Vector2(0.38, 0.42)], BLUE)
	_rrect(ci, k, 0.26, 0.42, 0.74, 1.8, 0.1, BLUE)
	_rect(ci, k, 0.26, 0.98, 0.74, 1.38, WHITE)
	_poly(ci, k, [Vector2(0.5, 1.04), Vector2(0.6, 1.22), Vector2(0.4, 1.22)], BLUE_DARK)
	_disc(ci, k, 0.5, 1.24, 0.1, BLUE_DARK)
	_line(ci, k, Vector2(0.34, 0.6), Vector2(0.34, 0.92), Color(1, 1, 1, 0.45), 0.05)


static func _jug(ci: CanvasItem, k: float) -> void:
	# the handle first (the body is over its root)
	ci.draw_arc(Vector2(1.7, 1.12) * k, 0.26 * k, -PI / 2.0, PI / 2.0, 14, OUT, 0.12 * k + lw(k) * 2.0, true)
	ci.draw_arc(Vector2(1.7, 1.12) * k, 0.26 * k, -PI / 2.0, PI / 2.0, 14, BLUE_DARK, 0.12 * k, true)
	_rect(ci, k, 0.8, 0.26, 1.2, 0.6, BLUE_PALE)
	_rrect(ci, k, 0.34, 0.6, 1.66, 1.88, 0.18, BLUE)
	_rect(ci, k, 0.5, 1.0, 1.5, 1.6, WHITE)
	_poly(ci, k, [Vector2(1.0, 1.08), Vector2(1.16, 1.34), Vector2(0.84, 1.34)], BLUE_DARK)
	_disc(ci, k, 1.0, 1.38, 0.17, BLUE_DARK)
	_line(ci, k, Vector2(0.48, 0.78), Vector2(0.48, 0.94), Color(1, 1, 1, 0.45), 0.06)


static func _bandage(ci: CanvasItem, k: float) -> void:
	# an adhesive dressing laid across the cell: a tan strip with a pale pad in the middle and a red stitch at each end (nothing else in the pack is a slanted strip)
	var a := deg_to_rad(-36.0)
	var c := Vector2(0.5, 0.5)
	_poly(ci, k, _turned([Vector2(-0.44, -0.17), Vector2(0.44, -0.17), Vector2(0.44, 0.17), Vector2(-0.44, 0.17)], a, c), STRIP)
	_poly(ci, k, _turned([Vector2(-0.15, -0.17), Vector2(0.15, -0.17), Vector2(0.15, 0.17), Vector2(-0.15, 0.17)], a, c), CREAM)
	for s in [-0.3, 0.3]:
		var p := c + Vector2(s, 0.0).rotated(a)
		_disc(ci, k, p.x, p.y, 0.045, RED)


static func _medkit(ci: CanvasItem, k: float) -> void:
	_rrect(ci, k, 0.76, 0.1, 1.24, 0.26, 0.05, GREY)
	_rrect(ci, k, 0.12, 0.22, 1.88, 0.88, 0.1, WHITE)
	_rect(ci, k, 0.78, 0.5, 1.22, 0.62, RED)
	_rect(ci, k, 0.94, 0.34, 1.06, 0.76, RED)
	_rect(ci, k, 0.78, 0.5, 1.22, 0.62, RED)
	_rect(ci, k, 0.2, 0.46, 0.34, 0.64, GREY)
	_rect(ci, k, 1.66, 0.46, 1.8, 0.64, GREY)


static func _unknown(ci: CanvasItem, k: float) -> void:
	_rrect(ci, k, 0.2, 0.2, 0.8, 0.8, 0.1, CREAM_DARK)
	ci.draw_string(ThemeDB.fallback_font, Vector2(0.38, 0.66) * k, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(k * 0.5), OUT)


# ----------------------------------------------------------------------------- equipment --

## The pump shotgun, side on, in `rect` (any size, the picture keeps its own proportions).
static func draw_gun(ci: CanvasItem, rect: Rect2) -> void:
	var k := minf(rect.size.x / 1.0, rect.size.y / 0.45)
	var o := rect.position + Vector2((rect.size.x - k) * 0.5, (rect.size.y - k * 0.45) * 0.5)
	ci.draw_set_transform(o, 0.0, Vector2.ONE)
	_rect(ci, k, 0.04, 0.06, 0.66, 0.14, STEEL)
	_rect(ci, k, 0.04, 0.16, 0.6, 0.22, STEEL)
	_rect(ci, k, 0.64, 0.02, 0.82, 0.26, GREY)
	_rect(ci, k, 0.34, 0.15, 0.52, 0.29, WOOD)
	_poly(ci, k, [Vector2(0.8, 0.06), Vector2(0.98, 0.16), Vector2(0.98, 0.4), Vector2(0.88, 0.4), Vector2(0.8, 0.26)], WOOD)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The swing of a blow, in `rect`: a thick arc with a streak, no item.
static func draw_melee(ci: CanvasItem, rect: Rect2) -> void:
	var k := minf(rect.size.x, rect.size.y)
	var c := rect.get_center() + Vector2(-k * 0.1, k * 0.15)
	var r := k * 0.38
	ci.draw_arc(c, r, -2.4, -0.5, 18, OUT, k * 0.17 + lw(k) * 2.0, true)
	ci.draw_arc(c, r, -2.4, -0.5, 18, CREAM, k * 0.17, true)
	ci.draw_arc(c, r * 0.78, -2.1, -0.8, 14, CREAM_DARK, k * 0.06, true)
	var tip := c + Vector2.from_angle(-0.5) * r
	ci.draw_circle(tip, k * 0.1, RED)
	ci.draw_arc(tip, k * 0.1, 0.0, TAU, 14, OUT, lw(k), true)


## A small backpack for the chip and the window's head, in `rect`: a domed body in `fill` with a pale rim (it is drawn on the dark boards), a handle, a flap and a pocket.
static func draw_pack(ci: CanvasItem, rect: Rect2, fill: Color, rim: Color = Color("#f2ecd8")) -> void:
	var k := minf(rect.size.x, rect.size.y)
	var o := rect.position + (rect.size - Vector2(k, k)) * 0.5
	var w := maxf(1.2, k * 0.08)
	var body := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		body.append(o + Vector2(0.5 + 0.38 * cos(a), 0.52 + 0.32 * sin(a)) * k)
	body.append(o + Vector2(0.86, 0.94) * k)
	body.append(o + Vector2(0.14, 0.94) * k)
	ci.draw_arc(o + Vector2(0.5, 0.2) * k, 0.13 * k, PI, TAU, 10, rim, w, true)
	ci.draw_colored_polygon(body, fill)
	var l := PackedVector2Array(body)
	l.append(body[0])
	ci.draw_polyline(l, rim, w, true)
	ci.draw_line(o + Vector2(0.14, 0.56) * k, o + Vector2(0.86, 0.56) * k, Color(OUT, 0.8), w, true)
	var pocket := Rect2(o + Vector2(0.3, 0.66) * k, Vector2(0.4, 0.2) * k)
	ci.draw_rect(pocket, Color(OUT, 0.45))
	ci.draw_rect(pocket, Color(OUT, 0.9), false, w * 0.8)
