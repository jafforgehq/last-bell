## The small marks of what the player has asked of people over the radio (round 24, the command wheel): one glyph for each verb, in a pill over
## the head of a person who carries the order (following, holding, covering, searching, walking to a post) and in the slices of the wheel
## (scripts/ui/command_wheel.gd), and the thin dotted line from the person to the spot of a hold, a search or a post. The views that draw
## them (the yard's overlay and a place's) ask `of_person` what a person carries and `spot_of` where it points.
##
## Cheap on purpose: a pill is one stylebox (made once for each kind, never in a frame) and a few lines; the dotted line one call. Nothing
## here allocates in a frame but the strings and rectangles of the draw calls themselves.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

## The verbs that leave a mark, in the radio's words ("come" is following).
const KINDS := ["come", "hold", "cover", "search", "back", "post"]
## The letter of a verb's glyph (the two that are arrows have none: they are drawn).
const LETTERS := {"hold": "H", "cover": "C", "search": "S", "post": "W"}
## What the glyph of each says it is when a person carries it, for the tooltip and a screen reader's word.
const WORDS := {"come": "Following you", "hold": "Holding a spot", "cover": "Covering you", "search": "Searching", "back": "Going back", "post": "Walking to the post"}
const COLORS := {
	"come": Color("#8ecae6"),
	"hold": Color("#f0c24a"),
	"cover": Color("#8fb85a"),
	"search": Color("#d9a0e0"),
	"back": Color("#c1c5b5"),
	"post": Color("#7fa6c9"),
}
## The stance the radio gives (`person.stance`) to the verb it came from.
const KIND_OF_STANCE := {"follow": "come", "hold": "hold", "cover": "cover", "search": "search"}

## A pill's size in pixels: the glyph is 12 px or more, so it reads over a figure at any zoom the yard has.
const PILL_W := 20.0
const PILL_H := 17.0
const GLYPH_R := 6.0
const INK := Color("#10140f")

static var _boxes := {}


static func color_of(kind: String) -> Color:
	return COLORS.get(kind, Color("#c1c5b5"))


## The mark a person carries: "come", "hold", "cover" or "search" (the stances the radio gave them), "post" (an order to a night post of the
## radio's "To the walls", which is a `Vector3` with a z above a half), else "". `p` is a person of the rules; anything else is "".
static func of_person(p) -> String:
	if p == null or typeof(p) != TYPE_OBJECT or not is_instance_valid(p):
		return ""
	var st = p.get("stance")
	if typeof(st) == TYPE_STRING and KIND_OF_STANCE.has(String(st)):
		return String(KIND_OF_STANCE[String(st)])
	var o = p.get("order")
	if typeof(o) == TYPE_VECTOR3 and Vector3(o).z > 0.5:
		return "post"
	return ""


## Where the order of a person points on the map (tiles), or Vector2.INF when it points nowhere (following and covering walk with you).
static func spot_of(p, kind: String) -> Vector2:
	if kind == "hold" or kind == "search":
		var at = p.get("stance_at")
		if typeof(at) == TYPE_VECTOR2 and Vector2(at) != Vector2.ZERO:
			return Vector2(at)
	elif kind == "post":
		var o = p.get("order")
		if typeof(o) == TYPE_VECTOR3:
			return Vector2(Vector3(o).x, Vector3(o).y)
	return Vector2.INF


## The pill's stylebox of a kind (made the first time it is asked for).
static func _box(kind: String) -> StyleBoxFlat:
	if _boxes.has(kind):
		return _boxes[kind]
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.043, 0.078, 0.067, 0.88)
	s.border_color = color_of(kind)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.anti_aliasing = true
	_boxes[kind] = s
	return s


## The glyph of a verb, centred on `c`, about `r` pixels from its centre to its edge, in `ink`. An arrow for come (to the right) and back
## (to the left), else its letter.
static func draw_glyph(ci: CanvasItem, kind: String, c: Vector2, r: float, ink: Color) -> void:
	if kind == "come" or kind == "back":
		var d := 1.0 if kind == "come" else -1.0
		var w := maxf(1.6, r * 0.28)
		ci.draw_line(c + Vector2(-0.62 * r * d, 0.0), c + Vector2(0.55 * r * d, 0.0), ink, w, true)
		ci.draw_polyline(PackedVector2Array([c + Vector2(0.02 * r * d, -0.52 * r), c + Vector2(0.62 * r * d, 0.0), c + Vector2(0.02 * r * d, 0.52 * r)]), ink, w, true)
		return
	var letter := String(LETTERS.get(kind, "?"))
	var font := Fonts.cond(700, 0)
	var fs := maxi(12, int(roundf(r * 2.0)))
	var tw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, c + Vector2(-tw * 0.5, fs * 0.34), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## A pill with the glyph of `kind` standing on `head` (the point a little over the figure's head: its middle and its foot), `alpha` for a fade.
## Returns the pill's rectangle.
static func draw_pill(ci: CanvasItem, kind: String, head: Vector2, alpha: float = 1.0) -> Rect2:
	var rect := Rect2(head.x - PILL_W * 0.5, head.y - PILL_H, PILL_W, PILL_H)
	ci.draw_style_box(_box(kind), rect)
	draw_glyph(ci, kind, rect.get_center(), GLYPH_R, Color(color_of(kind), alpha))
	return rect


## The thin dotted line from a person's feet to the spot they were sent to, and a small ring at the spot.
static func draw_link(ci: CanvasItem, kind: String, from: Vector2, to: Vector2, alpha: float = 1.0) -> void:
	var col := Color(color_of(kind), 0.78 * alpha)
	ci.draw_dashed_line(from, to, col, 1.5, 5.0, true, true)
	ci.draw_arc(to, 4.0, 0.0, TAU, 14, col, 1.5, true)
