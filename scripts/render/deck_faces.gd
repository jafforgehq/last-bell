## Gives the raised wooden platforms some height. The map's walkways and
## corner towers are flat plank sprites seen from above; in this slightly
## tilted view a raised thing shows its front (south) face: a scaffold of posts,
## rope-lashed braces and concrete footings standing on the ground, dark under
## the planks, with a shadow on the ground in front and ladders hooked over the
## edge. This draws those, from the pieces tools/make_deck_art.py cuts out of
## the reference pictures. Units are tiles; (x, y) is the map's, y growing south.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TILE := GD.TILE

## How tall a walkway and a tower stand, in tiles (what shows of the face), and
## how wide one bay of the scaffold is. The art is cut to these sizes.
const WALKWAY_HEIGHT := 1.3
const TOWER_HEIGHT := 1.9
const BAY_WIDTH := 1.25
## The pieces are drawn at this many pixels to the tile.
const ART_PX := 192.0
## A face's end piece (a post and the end of the top board) and one post piece:
## their widths, and how far from the end the end post's middle stands.
const CAP_WIDTH := 69.0 / ART_PX
const CAP_POST := 36.0 / ART_PX
const POST_WIDTH := 66.0 / ART_PX
## Which of the three bays comes next, so the same one does not repeat.
const BAY_ORDER := [0, 2, 1, 1, 0, 2, 0, 1, 2, 2, 1, 0]
## A ladder hung down a face: its size, and how far above the deck's edge it
## starts (the hooks go over the rail).
const LADDER_WIDTH := 0.62
const LADDER_LENGTH := 1.52
const LADDER_ABOVE := 0.12
## A ladder leaning out from the side of a walkway: its reach and its width.
const LADDER_LEAN := 1.35
const LADDER_SPAN := 0.56
## The supports along the inner edge of a side walkway (its edge shows to the
## yard, so its posts do): their width, how far below the walkway's north end the
## first one starts (clear of the north face) and how far apart they stand.
const LEG_WIDTH := 39.0 / ART_PX
const LEG_FIRST := 1.45
const LEG_SPACING := 2.45
## The shadow on the ground in front of a face: how far it reaches, how dark it
## starts, and how far it is thrown sideways (the light is from the north west).
const SHADOW_REACH := 1.4
const SHADOW_ALPHA := 0.72
const SHADOW_THROW := 0.35

const INK := Color("#241810")

## The decks to give a face: {"x0", "y0", "x1", "y1", "height", "tower"} (the
## deck's footprint on the map and how tall it stands).
var decks: Array = []
## Ladders: {"kind": "front", "x", "top"} hung down the south face of the north
## walkway, and {"kind": "west" or "east", "x", "y"} leaning against the side of
## the west or east one.
var ladders: Array = []
var _shadow: GradientTexture2D
var _shadow_h: GradientTexture2D
var _bays: Array = []
var _posts: Array = []
var _cap := {}
var _tower: Texture2D
var _leg: Texture2D
var _ladder: Texture2D
var _side := {}


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
			if o.kind != "ladder":
				continue
			if absf(sin(float(o.a))) < 0.5:
				# against the south face of the north walkway
				ladders.append({"kind": "front", "x": float(o.cx), "top": float(decks[0].y1) - LADDER_ABOVE - 0.02})
			else:
				# against the inner side of the west or east walkway
				ladders.append({"kind": "west" if float(o.cx) < 42.0 else "east", "x": float(o.cx), "y": float(o.cy)})
	_load_art()
	_shadow = _gradient(Vector2(0.0, 1.0), 4, 64)
	_shadow_h = _gradient(Vector2(1.0, 0.0), 64, 4)
	queue_redraw()


func _load_art() -> void:
	var dir := "res://assets/objects/deck_"
	for i in 3:
		_bays.append(GD.tex("%sface_bay_%d.png" % [dir, i]))
	for i in 2:
		_posts.append(GD.tex("%sface_post_%d.png" % [dir, i]))
	_cap = {"w": GD.tex(dir + "face_cap_w.png"), "e": GD.tex(dir + "face_cap_e.png")}
	_tower = GD.tex(dir + "face_tower.png")
	_leg = GD.tex(dir + "leg.png")
	_ladder = GD.tex(dir + "ladder_front.png")
	_side = {"west": GD.tex(dir + "ladder_side_w.png"), "east": GD.tex(dir + "ladder_side_e.png")}


func _gradient(to: Vector2, w: int, h: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, SHADOW_ALPHA), Color(0, 0, 0, SHADOW_ALPHA * 0.45), Color(0, 0, 0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2.ZERO
	t.fill_to = to
	t.width = w
	t.height = h
	return t


## Where the posts of a face from x0 to x1 stand (the middle of each, from the
## first to the last): the end posts stand a little in from the ends and the
## bays between them are all the same width, about BAY_WIDTH.
static func post_positions(x0: float, x1: float) -> PackedFloat32Array:
	var first := x0 + CAP_POST
	var span := (x1 - CAP_POST) - first
	var n := maxi(1, roundi(span / BAY_WIDTH))
	var posts := PackedFloat32Array()
	for i in n + 1:
		posts.append(first + span * float(i) / float(n))
	return posts


## Where the supports along a side walkway from y0 to y1 stand (the top of each,
## going south): they hang a face's height below that, so the last one's foot is
## not far past the walkway's end.
static func leg_positions(y0: float, y1: float) -> PackedFloat32Array:
	var legs := PackedFloat32Array()
	var y := y0 + LEG_FIRST
	while y + WALKWAY_HEIGHT <= y1 + 0.3:
		legs.append(y)
		y += LEG_SPACING
	return legs


## Whether a leg from y down a face's height would stand behind a ladder that
## leans against the same side.
func _ladder_in_the_way(west: bool, y: float, height: float) -> bool:
	for l in ladders:
		if l.kind == ("west" if west else "east") and float(l.y) + LADDER_SPAN / 2.0 > y and float(l.y) - LADDER_SPAN / 2.0 < y + height:
			return true
	return false


func _draw() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY.scaled(Vector2(TILE, TILE)))
	for d in decks:
		_draw_deck(d)
	for l in ladders:
		if l.kind == "front":
			_draw_ladder(l)
		else:
			_draw_side_ladder(l)


func _draw_deck(d: Dictionary) -> void:
	var x0: float = d.x0
	var x1: float = d.x1
	var depth: float = d.y1 - d.y0
	if d.tower:
		_draw_tower(d)
		return
	if depth > x1 - x0:
		# a walkway along the west or east wall: its inner side is edge-on, so it
		# shows a shadow (the light is from the north west, so the west walkway
		# throws one across the yard and the east one only a thin dark line at its
		# foot) and its south end shows a short face; the planks are the sprite's
		var west: bool = (x0 + x1) / 2.0 < 42.0
		if west:
			draw_texture_rect(_shadow_h, Rect2(x1 - 0.02, d.y0 + 0.25, SHADOW_REACH, depth - 0.1), false)
			draw_rect(Rect2(x1 - 0.01, d.y0 + 0.25, 0.08, depth - 0.1), Color(0, 0, 0, 0.3))
		else:
			draw_rect(Rect2(x0 - 0.09, d.y0 + 0.2, 0.1, depth - 0.1), Color(0, 0, 0, 0.3))
		# the supports stand just outside the inner edge, hanging down from it
		var leg_x := x1 - 0.03 if west else x0 + 0.03 - LEG_WIDTH
		for y in leg_positions(d.y0, d.y1):
			if not _ladder_in_the_way(west, y, d.height):
				draw_texture_rect(_leg, Rect2(leg_x, y - 0.02, LEG_WIDTH, d.height), false)
	_draw_face(x0, x1, d.y1, d.height)


## The front face of a walkway whose south edge is at y = ys: the shadow on the
## ground, then the bays of the scaffold, the posts between them and the ends.
func _draw_face(x0: float, x1: float, ys: float, fh: float) -> void:
	var w := x1 - x0
	draw_texture_rect(_shadow, Rect2(x0 + SHADOW_THROW * fh, ys + fh - 0.04, w, SHADOW_REACH), false)
	var posts := post_positions(x0, x1)
	for i in posts.size() - 1:
		var bay_tex: Texture2D = _bays[BAY_ORDER[i % BAY_ORDER.size()]]
		draw_texture_rect(bay_tex, Rect2(posts[i], ys - 0.02, posts[i + 1] - posts[i], fh), false)
	for i in range(1, posts.size() - 1):
		var post_tex: Texture2D = _posts[(i * 7 + 3) % 2]
		draw_texture_rect(post_tex, Rect2(posts[i] - POST_WIDTH / 2.0, ys - 0.02, POST_WIDTH, fh), false)
	draw_texture_rect(_cap.w, Rect2(x0, ys - 0.02, CAP_WIDTH, fh), false)
	draw_texture_rect(_cap.e, Rect2(x1 - CAP_WIDTH, ys - 0.02, CAP_WIDTH, fh), false)


## The base of a corner tower: legs, two tiers of braces, the footings, and a
## shadow that falls to the south east.
func _draw_tower(d: Dictionary) -> void:
	var tw := _tower.get_width() / ART_PX
	var th := _tower.get_height() / ART_PX
	var cx := (float(d.x0) + float(d.x1)) / 2.0
	var ys: float = d.y1
	draw_texture_rect(_shadow, Rect2(cx - tw / 2.0 + SHADOW_THROW * th, ys + th - 0.06, tw, SHADOW_REACH), false)
	draw_texture_rect(_tower, Rect2(cx - tw / 2.0, ys - 0.02, tw, th), false)


## A ladder seen from the front, hooked over the rail and standing on the
## ground at the foot of the face.
func _draw_ladder(l: Dictionary) -> void:
	var x: float = l.x
	var top: float = l.top
	# its shadow on the face, the ladder's own shape a little to the south east
	draw_texture_rect(_ladder, Rect2(x - LADDER_WIDTH / 2.0 + 0.07, top + 0.07, LADDER_WIDTH, LADDER_LENGTH), false, Color(0, 0, 0, 0.45))
	draw_texture_rect(_ladder, Rect2(x - LADDER_WIDTH / 2.0, top, LADDER_WIDTH, LADDER_LENGTH), false)


## A ladder against the side of a west or east walkway, seen from above: it
## leans out from the deck's edge into the yard, with a shadow.
func _draw_side_ladder(l: Dictionary) -> void:
	var west: bool = l.kind == "west"
	var cy: float = l.y
	var edge: float = 21.55 if west else 62.45
	var x0: float = edge - 0.2 if west else edge + 0.2 - LADDER_LEAN
	draw_texture_rect(_side[l.kind], Rect2(x0 + (0.1 if west else -0.05), cy - LADDER_SPAN / 2.0 + 0.06, LADDER_LEAN, LADDER_SPAN), false, Color(0, 0, 0, 0.4))
	draw_texture_rect(_side[l.kind], Rect2(x0, cy - LADDER_SPAN / 2.0, LADDER_LEAN, LADDER_SPAN), false)
