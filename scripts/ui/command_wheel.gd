## The command wheel (round 24): hold C (or the middle button) and a ring of six slices opens round the pointer, one for each verb of the radio
## (Come with me, Hold here, Cover me, Search that, Go back, To the walls); release over a slice, or click it, and the person it is for is asked.
## A VIEW only: it draws what the controller (scripts/ui/wheel_ctl.gd) tells it and says where the pointer is; it never reads the game, never
## asks the radio and never takes the mouse (the controller gets the events first). It does not pause anything.
##
##   wheel.open_at(screen, {"title": "Dez", "caption": "", "slices": [...], "group": false})   # a slice: {"verb", "name", "enabled", "soft", "tip"}
##   wheel.move_pointer(pos)       # the pointer moved; the slice under it lights once it has moved a little (`armed`)
##   wheel.choice_at(pos)          # {"zone": "slice" | "centre" | "out", "index"} of a point: what a click or a release there would pick
##   wheel.close()
##
## The ring is 252 px across with a slice's glyph, name and, for a soft refusal, an "Insist" mark; its centre names the person (or "Everyone near
## you" with the second ring: the same verbs for everyone within eight tiles) and the line under the ring says what the slice under the pointer
## would do, or why it cannot. The ring is kept inside the window; the pointer then starts off-centre, so no slice lights until the pointer has
## moved (`armed`), and a release before that picks nothing. Drawn only when something changes: nothing at all while it is shut.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const StanceMarks := preload("res://scripts/render/stance_marks.gd")

const N := 6
const R_IN := 42.0
const R_OUT := 126.0
## The second ring (everyone near): a band just outside the first.
const R_GROUP := 138.0
## A pointer farther than this from the middle is outside the wheel: a release or a click there cancels.
const R_FAR := R_OUT + 48.0
## The room the line under the ring keeps below it, and the margin to the window's edge.
const LINE_H := 64.0
const MARGIN := 6.0
## The pointer has to move this far from where it opened before a slice can light.
const ARM_PX := 5.0
const GAP := 0.04

const INK := Color("#eeeadd")
const INK2 := Color("#c1c5b5")
const ACCENT := Color("#f0c24a")
const WARN := Color("#e8953a")
const DARK := Color(0.043, 0.078, 0.067, 0.94)
const SLICE := Color(0.106, 0.165, 0.149, 0.95)
const SLICE_HOT := Color(0.30, 0.25, 0.09, 0.98)
const SLICE_SOFT_HOT := Color(0.31, 0.19, 0.07, 0.98)
const SLICE_OFF := Color(0.075, 0.105, 0.095, 0.82)
const EDGE := Color(0.93, 0.96, 0.89, 0.22)

## Whether the wheel is up, where its middle is (inside the window), where it was opened and where the pointer is.
var active := false
var centre := Vector2.ZERO
var origin := Vector2.ZERO
var pointer := Vector2.ZERO
## The pointer has moved since the wheel opened (a slice lights, a release picks).
var armed := false
## Opened with a tap of the key: it stays up until a click picks a slice, or the centre, the outside or Esc cancels it.
var latched := false
## The second ring: the same verbs for everyone near the avatar.
var group := false
var title := ""
var caption := ""
## [{"verb", "name", "enabled" (false: greyed), "soft" (a refusal that insisting can override), "tip" (the line under the ring)}], in the radio's order.
var slices: Array = []
## What the line under the ring says when no slice is lit.
var hint := ""
## The slice the pointer is on (-1: none, the centre, outside or not yet armed).
var hover := -1
var over_centre := false
## How many times it was drawn (a test reads it: a wheel that is shut draws nothing).
var drawn := 0

var _polys: Array = []
var _edges: Array = []
var _line_box: StyleBoxFlat


func _init() -> void:
	name = "CommandWheel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 40
	_line_box = StyleBoxFlat.new()
	_line_box.bg_color = Color(0.043, 0.078, 0.067, 0.94)
	_line_box.border_color = Color(EDGE, 0.5)
	_line_box.set_border_width_all(1)
	_line_box.set_corner_radius_all(6)
	_line_box.set_content_margin_all(6)
	_line_box.anti_aliasing = true
	_make_shapes()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ----------------------------------------------------------------- geometry --

## The slice a point `off` from the middle is on: 0 to N-1 clockwise from the top (the first is the one straight up), -1 in the centre, -2 outside
## (farther than R_FAR). Pure.
static func slice_at(off: Vector2, n: int = N) -> int:
	var d := off.length()
	if d < R_IN:
		return -1
	if d > R_FAR:
		return -2
	var k := TAU / float(n)
	return int(fposmod(atan2(off.x, -off.y) + k * 0.5, TAU) / k) % n


## The middle of slice `i` (from the wheel's middle), halfway between the rings.
static func slice_mid(i: int, n: int = N, radius: float = (R_IN + R_OUT) * 0.5) -> Vector2:
	var a := TAU * float(i) / float(n) - PI * 0.5
	return Vector2(cos(a), sin(a)) * radius


func _make_shapes() -> void:
	var k := TAU / float(N)
	for i in N:
		var a := TAU * float(i) / float(N) - PI * 0.5
		var a0 := a - k * 0.5 + GAP
		var a1 := a + k * 0.5 - GAP
		var poly := PackedVector2Array()
		var segs := 12
		for s in segs + 1:
			var t := a0 + (a1 - a0) * float(s) / float(segs)
			poly.append(Vector2(cos(t), sin(t)) * R_OUT)
		for s in segs + 1:
			var t := a1 - (a1 - a0) * float(s) / float(segs)
			poly.append(Vector2(cos(t), sin(t)) * R_IN)
		_polys.append(poly)
		var edge := PackedVector2Array(poly)
		edge.append(poly[0])
		_edges.append(edge)


# ------------------------------------------------------------------- state --

## Opens the wheel with its middle at `screen` (kept inside the window, with room under it for the line). `info`: "title", "caption", "slices",
## "group", "hint", "latched".
func open_at(screen: Vector2, info: Dictionary = {}) -> void:
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 800.0)
	var rr := R_GROUP + MARGIN
	centre = Vector2(clampf(screen.x, rr, maxf(rr, view.x - rr)), clampf(screen.y, rr, maxf(rr, view.y - rr - LINE_H)))
	origin = screen
	pointer = screen
	armed = false
	latched = bool(info.get("latched", false))
	active = true
	visible = true
	hover = -1
	over_centre = false
	set_info(info)


## Gives the wheel new words (the controller does it when the target, the ring or the game changes while it is up).
func set_info(info: Dictionary) -> void:
	if info.has("title"):
		title = String(info.title)
	if info.has("caption"):
		caption = String(info.caption)
	if info.has("slices"):
		slices = info.slices
	if info.has("group"):
		group = bool(info.group)
	if info.has("hint"):
		hint = String(info.hint)
	_aim()
	queue_redraw()


func close() -> void:
	active = false
	visible = false
	armed = false
	latched = false
	hover = -1
	over_centre = false


## The pointer is at `pos` now.
func move_pointer(pos: Vector2) -> void:
	pointer = pos
	if not armed and pos.distance_to(origin) >= ARM_PX:
		armed = true
	_aim()


## What is under a point: {"zone": "slice" | "centre" | "out", "index" (the slice, else -1)}.
func choice_at(pos: Vector2) -> Dictionary:
	var k := slice_at(pos - centre)
	if k == -1:
		return {"zone": "centre", "index": -1}
	if k == -2:
		return {"zone": "out", "index": -1}
	return {"zone": "slice", "index": k}


## What a release would pick where the pointer is now: nothing before it has moved.
func choice_now() -> Dictionary:
	if not armed:
		return {"zone": "none", "index": -1}
	return choice_at(pointer)


## The slice and the centre lit by the pointer.
func _aim() -> void:
	var was := hover
	var was_centre := over_centre
	var c := choice_now()
	hover = int(c.index) if String(c.zone) == "slice" else -1
	over_centre = String(c.zone) == "centre"
	if hover != was or over_centre != was_centre:
		queue_redraw()


## The words of the line under the ring: the lit slice's, else the hint.
func line_text() -> String:
	if hover >= 0 and hover < slices.size():
		return String(slices[hover].get("tip", ""))
	if over_centre:
		return "Click the middle: %s" % ("back to one person" if group else "the same verbs for everyone near you")
	return hint


# ---------------------------------------------------------------- the drawing --

func _draw() -> void:
	if not active:
		return
	drawn += 1
	draw_set_transform(centre, 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, R_OUT + 8.0, Color(0.02, 0.04, 0.035, 0.5))
	if group:
		# the second ring: a gold band round the first (everyone within eight tiles)
		draw_arc(Vector2.ZERO, R_GROUP - 3.0, 0.0, TAU, 72, Color(ACCENT, 0.9), 6.0, true)
		draw_arc(Vector2.ZERO, R_GROUP + 1.5, 0.0, TAU, 72, Color(0.04, 0.03, 0.02, 0.6), 1.5, true)
	var name_font := Fonts.cond(700, 0)
	var small := Fonts.sans(600, 0)
	for i in mini(N, slices.size()):
		var s: Dictionary = slices[i]
		var on: bool = bool(s.get("enabled", true))
		var soft: bool = bool(s.get("soft", false))
		var lit := i == hover and (on or soft)
		var fill := SLICE if on or soft else SLICE_OFF
		var edge := Color(EDGE, 0.7)
		if lit:
			fill = SLICE_SOFT_HOT if soft else SLICE_HOT
		if soft:
			edge = Color(WARN, 0.95 if lit else 0.7)
		elif lit:
			edge = ACCENT
		draw_colored_polygon(_polys[i], fill)
		draw_polyline(_edges[i], edge, 2.6 if lit else 1.3, true)
		var verb := String(s.get("verb", ""))
		var alpha := 1.0 if (on or soft) else 0.38
		var mid := slice_mid(i)
		var gc := mid + Vector2(0.0, -12.0)
		draw_circle(gc, 13.0, Color(0.02, 0.04, 0.035, 0.7 * alpha))
		draw_arc(gc, 13.0, 0.0, TAU, 20, Color(StanceMarks.color_of(verb), 0.8 * alpha), 1.5, true)
		StanceMarks.draw_glyph(self, verb, gc, 7.5, Color(StanceMarks.color_of(verb), alpha))
		var label := String(s.get("name", verb))
		var fs := 14
		var tw := name_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ink := Color(ACCENT if lit else INK, alpha)
		draw_string(name_font, mid + Vector2(-tw * 0.5, 17.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		if soft:
			var word := "Insist"
			var ww := small.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(small, mid + Vector2(-ww * 0.5, 31.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(WARN, 0.95))
	# the middle: who it is for
	draw_circle(Vector2.ZERO, R_IN - 3.0, SLICE_HOT if over_centre else DARK)
	draw_arc(Vector2.ZERO, R_IN - 3.0, 0.0, TAU, 32, ACCENT if (over_centre or group) else Color(EDGE, 0.8), 2.0 if over_centre else 1.3, true)
	var head := title if title != "" else "Nobody"
	var hf := 17
	var hw := name_font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hf).x
	if hw > R_IN * 1.7:
		hf = 14
		hw = name_font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hf).x
	draw_string(name_font, Vector2(-hw * 0.5, 2.0 if caption != "" else 6.0), head, HORIZONTAL_ALIGNMENT_LEFT, -1, hf, INK)
	if caption != "":
		var cw := small.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(small, Vector2(-cw * 0.5, 17.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the line under the ring
	var text := line_text()
	if text != "":
		var view := get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 800.0)
		var w := minf(340.0, maxf(160.0, view.x - 2.0 * MARGIN - 12.0))
		var font := Fonts.sans(600, 0)
		var inner := w - 12.0
		var box := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, inner, 13, 3)
		var rect := Rect2(clampf(centre.x - w * 0.5, MARGIN, maxf(MARGIN, view.x - w - MARGIN)), centre.y + (R_GROUP if group else R_OUT) + 12.0, w, box.y + 12.0)
		draw_style_box(_line_box, rect)
		var warn_line := hover >= 0 and hover < slices.size() and (bool(slices[hover].get("soft", false)) or not bool(slices[hover].get("enabled", true)))
		draw_multiline_string(font, rect.position + Vector2(6.0, 6.0 + font.get_ascent(13)), text, HORIZONTAL_ALIGNMENT_LEFT, inner, 13, 3, Color(WARN if warn_line else INK))
