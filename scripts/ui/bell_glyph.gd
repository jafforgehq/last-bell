## A brass bell, drawn with polygons so that it is sharp at any size (the title's mark). It
## hangs from a ring and sways a little, with the clapper a beat behind, unless `sway` is off
## (reduce motion).
extends Control

## The bell is drawn in a box of 100 by 120 units and scaled to fit the control.
const BOX := Vector2(100.0, 120.0)
const CENTER_X := 50.0
## The ring it hangs from, the half widths of the body going down (y, half width), the lip
## and the clapper, in units.
const RING := Vector2(50.0, 9.0)
const RING_R := 7.0
const PROFILE := [
	[17.0, 6.0], [19.0, 9.5], [23.0, 13.5], [29.0, 17.5], [37.0, 20.5], [47.0, 23.0], [58.0, 26.0],
	[68.0, 30.0], [77.0, 36.0], [84.0, 43.0], [89.0, 48.0],
]
const LIP_Y := 86.0
const LIP_H := 9.0
const LIP_HALF := 50.0
const CLAPPER := Vector2(50.0, 102.0)
const CLAPPER_R := 7.5
## Brass from the lit side to the shaded one.
const LIGHT := Color("#f7e29c")
const MID := Color("#e2b343")
const DEEP := Color("#b98a2b")
const SHADE := Color("#6b4a14")
const RIM := Color("#5a3d10")

var sway := true
var t := 0.0
## Seconds since the bell was struck (-1: it is not ringing).
var toll_t := -1.0
var _ramp: Gradient


func _init() -> void:
	custom_minimum_size = Vector2(60, 72)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ramp = Gradient.new()
	_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.68, 1.0])
	_ramp.colors = PackedColorArray([LIGHT, MID, DEEP, SHADE])


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if toll_t >= 0.0:
		toll_t += delta
		if toll_t > 6.0:
			toll_t = -1.0
		queue_redraw()
	if sway:
		t += delta
		queue_redraw()


## Strikes the bell: it swings wide and settles (nothing moves when `sway` is off: less motion).
func toll() -> void:
	if sway:
		toll_t = 0.0


## The outline of the body as a polygon (right side down, left side up), in units.
static func body_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in PROFILE:
		pts.append(Vector2(CENTER_X + float(p[1]), float(p[0])))
	for i in range(PROFILE.size() - 1, -1, -1):
		pts.append(Vector2(CENTER_X - float(PROFILE[i][1]), float(PROFILE[i][0])))
	return pts


func _draw() -> void:
	var k := minf(size.x / BOX.x, size.y / BOX.y)
	if k <= 0.0:
		return
	var origin := (size - BOX * k) / 2.0
	var angle := sin(t * 1.15) * 0.06 if sway else 0.0
	if toll_t >= 0.0:
		angle += exp(-toll_t * 0.75) * sin(toll_t * 5.2) * 0.32
	# swing about the ring; the clapper trails the swing
	draw_set_transform(origin + RING * k, angle, Vector2(k, k))
	var o := -RING
	# the ring
	draw_arc(o + RING, RING_R, 0.0, TAU, 28, RIM, 4.6, true)
	draw_arc(o + RING, RING_R, 0.0, TAU, 28, MID, 2.6, true)
	# the clapper, behind the lip
	var clap := o + CLAPPER + Vector2(-sin(t * 1.15 - 0.7) * 3.0 if sway else 0.0, 0.0)
	draw_circle(clap, CLAPPER_R + 1.2, RIM)
	draw_circle(clap, CLAPPER_R, DEEP)
	draw_circle(clap + Vector2(-2.2, -2.2), 2.6, LIGHT)
	# the body, lit from the left
	var pts := body_points()
	var cols := PackedColorArray()
	for p in pts:
		cols.append(_ramp.sample(clampf((p.x - CENTER_X) / 96.0 + 0.4, 0.0, 1.0)))
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + o)
	draw_polygon(moved, cols)
	draw_polyline(_closed(moved), RIM, 1.6, true)
	# the lip, a band across the bottom
	var lip := Rect2(o + Vector2(CENTER_X - LIP_HALF, LIP_Y), Vector2(LIP_HALF * 2.0, LIP_H))
	draw_rect(lip, RIM)
	draw_rect(lip.grow(-1.4), DEEP)
	draw_rect(Rect2(lip.position + Vector2(1.4, 1.4), Vector2(lip.size.x * 0.34, 2.4)), LIGHT)
	# a glint down the lit side
	var glint := PackedVector2Array()
	for p in PROFILE:
		glint.append(o + Vector2(CENTER_X - float(p[1]) * 0.62, float(p[0]) + 4.0))
	glint.resize(PROFILE.size() - 1)
	draw_polyline(glint, Color(1.0, 0.97, 0.82, 0.55), 2.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
