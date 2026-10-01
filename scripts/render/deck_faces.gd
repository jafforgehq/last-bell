## Gives the raised wooden platforms some height. The map's walkways and
## corner towers are flat plank sprites seen from above; in this slightly
## tilted view a raised thing shows its front (south) face, stands on posts and
## throws a shadow on the ground. This draws those: a plank face with posts and
## cross braces under the south edge, a shadow below it, and a ladder down the
## face. Units are tiles; (x, y) is the map's, y growing south.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TILE := GD.TILE

## How tall a walkway and a tower stand, in tiles (what shows of the face).
const WALKWAY_HEIGHT := 0.72
const TOWER_HEIGHT := 1.15
## How far the shadow reaches below the face, as a share of its height.
const SHADOW_REACH := 1.5
const SHADOW_ALPHA := 0.72

const FACE := Color("#775634")
const FACE_LINE := Color("#5a3f26")
const FACE_LIGHT := Color("#a47a4a")
const POST := Color("#4a3320")
const POST_LIGHT := Color("#6f5033")
const INK := Color("#241810")
const STEEL := Color("#99a1aa")
const STEEL_DARK := Color("#4a5058")

## The decks to give a face: {"x0", "y0", "x1", "y1", "height"} (the deck's
## footprint on the map and how tall it stands).
var decks: Array = []
## Ladders that go down a face: {"x", "top", "bottom"}.
var ladders: Array = []
var _shadow: GradientTexture2D
var _shadow_h: GradientTexture2D


## `kinds` are the object kinds to treat as decks ("walkway", "tower"). A
## walkway wider than it is deep gets a south face; a deep one (along the west
## and east walls) gets only a short face at its south end.
func setup(data: Dictionary, kinds: Array) -> void:
	for o in data.objects:
		if not (o.kind in kinds):
			continue
		var h := WALKWAY_HEIGHT if o.kind == "walkway" else TOWER_HEIGHT
		var half_w := float(o.w) / 2.0
		var half_h := float(o.h) / 2.0
		decks.append({"x0": float(o.cx) - half_w, "y0": float(o.cy) - half_h, "x1": float(o.cx) + half_w, "y1": float(o.cy) + half_h, "height": h, "tower": o.kind == "tower"})
	if "walkway" in kinds:
		for o in data.objects:
			# the three ladders on the north walkway: the others stay as they are
			if o.kind == "ladder" and absf(float(o.a)) < 0.01:
				ladders.append({"x": float(o.cx), "top": float(o.cy) - 0.6, "bottom": float(o.cy) - 0.6 + WALKWAY_HEIGHT + 0.22})
	_shadow = GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, SHADOW_ALPHA), Color(0, 0, 0, SHADOW_ALPHA * 0.62), Color(0, 0, 0, 0.0)])
	_shadow.gradient = g
	_shadow.fill = GradientTexture2D.FILL_LINEAR
	_shadow.fill_from = Vector2(0.0, 0.0)
	_shadow.fill_to = Vector2(0.0, 1.0)
	_shadow.width = 4
	_shadow.height = 64
	_shadow_h = GradientTexture2D.new()
	_shadow_h.gradient = g
	_shadow_h.fill = GradientTexture2D.FILL_LINEAR
	_shadow_h.fill_from = Vector2(0.0, 0.0)
	_shadow_h.fill_to = Vector2(1.0, 0.0)
	_shadow_h.width = 64
	_shadow_h.height = 4
	queue_redraw()


func _draw() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY.scaled(Vector2(TILE, TILE)))
	for d in decks:
		_draw_deck(d)
	for l in ladders:
		_draw_ladder(l)


func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


func _draw_deck(d: Dictionary) -> void:
	var x0: float = d.x0
	var x1: float = d.x1
	var ys: float = d.y1
	var fh: float = d.height
	var w := x1 - x0
	var depth: float = d.y1 - d.y0
	if depth > w:
		# a walkway along the west or east wall: its south end shows a short face
		# and its inner side a shadow (the light is from the north west, so the
		# west walkway throws one across the yard and the east one only a thin
		# dark line at its foot); the planks themselves are the sprite's
		var west: bool = (x0 + x1) / 2.0 < 42.0
		var reach: float = fh * SHADOW_REACH
		if west:
			draw_texture_rect(_shadow_h, Rect2(x1 - 0.02, d.y0 + 0.25, reach, depth - 0.1), false)
			draw_rect(Rect2(x1 - 0.01, d.y0 + 0.25, 0.08, depth - 0.1), Color(0, 0, 0, 0.3))
		else:
			draw_rect(Rect2(x0 - 0.09, d.y0 + 0.2, 0.1, depth - 0.1), Color(0, 0, 0, 0.3))
		_draw_face(x0, x1, ys, fh * 0.9)
		return
	_draw_face(x0, x1, ys, fh)


## The front face of a deck whose south edge is at y = ys: the shadow on the
## ground, the planking, the posts and braces.
func _draw_face(x0: float, x1: float, ys: float, fh: float) -> void:
	var w := x1 - x0
	# the shadow on the ground, longer for a taller deck
	var reach := fh * SHADOW_REACH
	draw_texture_rect(_shadow, Rect2(x0 + 0.05 + fh * 0.3, ys + fh - 0.02, w, reach), false)
	# a darker strip right at the foot where the posts meet the ground
	draw_rect(Rect2(x0 + 0.02, ys + fh - 0.01, w - 0.04, 0.1), Color(0, 0, 0, 0.45))
	# the planking: a dark body, two board lines, a light lip just under the rail
	_rect(x0, ys - 0.02, w, fh + 0.04, INK)
	_rect(x0 + 0.03, ys, w - 0.06, fh - 0.01, FACE)
	var boards := 3 if fh > 0.7 else 2
	for i in range(1, boards):
		var y := ys + fh * float(i) / float(boards)
		_rect(x0 + 0.03, y - 0.012, w - 0.06, 0.024, FACE_LINE)
		_rect(x0 + 0.03, y + 0.012, w - 0.06, 0.012, FACE_LIGHT)
	_rect(x0 + 0.03, ys, w - 0.06, 0.05, FACE_LIGHT)
	_rect(x0 + 0.03, ys + 0.05, w - 0.06, 0.025, FACE_LINE)
	# posts and cross braces, with a gap at each ladder
	var span := 2.0 if w > 6.0 else (w - 0.36) / maxf(1.0, round((w - 0.36) / 1.3))
	var n := int(round((w - 0.36) / span))
	for i in range(n + 1):
		var px := x0 + 0.18 + span * float(i)
		if px > x1 - 0.1:
			px = x1 - 0.18
		_post(px, ys, fh)
		if i < n:
			var nx := x0 + 0.18 + span * float(i + 1)
			if nx > x1 - 0.1:
				nx = x1 - 0.18
			_brace(px + 0.08, nx - 0.08, ys, fh)


func _post(x: float, ys: float, fh: float) -> void:
	_rect(x - 0.095, ys - 0.02, 0.19, fh + 0.07, INK)
	_rect(x - 0.075, ys, 0.15, fh + 0.04, POST)
	_rect(x - 0.075, ys, 0.045, fh + 0.04, POST_LIGHT)


func _brace(xa: float, xb: float, ys: float, fh: float) -> void:
	var ya := ys + 0.06
	var yb := ys + fh - 0.05
	draw_line(Vector2(xa, ya), Vector2(xb, yb), Color(INK, 0.9), 0.07)
	draw_line(Vector2(xa, ya), Vector2(xb, yb), Color(POST, 0.95), 0.045)
	draw_line(Vector2(xb, ya), Vector2(xa, yb), Color(INK, 0.9), 0.07)
	draw_line(Vector2(xb, ya), Vector2(xa, yb), Color(POST, 0.95), 0.045)


## A ladder seen from the front, hooked over the rail and standing on the
## ground at the foot of the face.
func _draw_ladder(l: Dictionary) -> void:
	var x: float = l.x
	var top: float = l.top
	var bottom: float = l.bottom
	var half := 0.26
	# its shadow on the face and the ground
	draw_rect(Rect2(x - half + 0.07, top + 0.06, half * 2.0, bottom - top), Color(0, 0, 0, 0.22))
	for side in [-1.0, 1.0]:
		var rx: float = x + side * half
		_rect(rx - 0.055, top, 0.11, bottom - top, INK)
		_rect(rx - 0.035, top + 0.01, 0.07, bottom - top - 0.02, STEEL)
		_rect(rx - 0.035, top + 0.01, 0.022, bottom - top - 0.02, Color(1, 1, 1, 0.22))
	var rungs := 5
	for i in rungs:
		var ry := top + 0.1 + (bottom - top - 0.2) * float(i) / float(rungs - 1)
		_rect(x - half, ry - 0.035, half * 2.0, 0.07, INK)
		_rect(x - half + 0.02, ry - 0.02, half * 2.0 - 0.04, 0.04, STEEL_DARK)
		_rect(x - half + 0.02, ry - 0.02, half * 2.0 - 0.04, 0.014, STEEL)
