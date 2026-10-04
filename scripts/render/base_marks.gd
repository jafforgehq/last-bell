## The world marks of the base's trouble (round 25, V25.2 PROBLEMS-VIEW of docs/superpowers/plans/2026-10-04-round-25.md; avatar mode only; a view:
## nothing here changes the rules). The overlay (scripts/render/overlay_node.gd) calls `draw` once a frame, from inside its own `_draw`, with itself as the
## canvas:
##
##   var marks := BaseMarks.new()                    # the overlay keeps one
##   marks.draw(canvas, sim, to_screen, opts)        # to_screen: Callable(tile Vector2) -> pixel Vector2; opts: see `draw`
##
## What it puts on the world, from what the rules say and nothing else:
##   PROBLEMS (`sim.problems.marks()`, round 25's S25.3): at the place of each open one a pulsing ring on the ground (amber at stage 0 and 1, red at
##     stage 2 and past its time; steady with reduced motion), over it a round badge with the kind's glyph (a drop for a leak, a bolt for a jam, a
##     speech bubble between the two for a quarrel, a crack for a wall), a thin ring round the badge that is the time that is left, and the rules' own
##     words in a pill over it ("Leak: 11 h left"); while someone else is on it a second pill under the ring says who ("Dez is on the way").
##   THE FIX RING (`sim.problems.fixing`): while the avatar's own hands are at one, a ring round the body fills as the work goes, like the bench's.
##   THE QUARANTINE SIGN (`sim.dilemmas.marks()`): a badge and its words where the rules put it (the bunk house).
##   FACILITY LABELS (`sim.briefing.facilities()`): what a station that is not working waits on ("Workshop: waiting on scrap"), in a small pill by the
##     building, while the avatar is within FACILITY_NEAR tiles of it or the Base page is open (`opts.base_page`).
## Every read is guarded (`get`, `has_method`): a sim with no such module draws nothing and says nothing.
##
## CHEAP (the web build's budget is tight): the lists are asked for 4 times a second and 2 times a second, not every frame; everything off the window
## is skipped before a call is made; the glyphs are constant polygons drawn through the canvas's transform; the pills are one cached stylebox; the
## widths of the words are remembered; nothing is allocated in a frame that has nothing new to draw. `record` (a test sets it) keeps what was drawn in
## `tags` for the tests to read.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

## The HUD's own colours (hud.gd: WARN, DANGER_TEXT, OK, INFO, INK, INK2), copied so that the renderer does not have to load the HUD.
const AMBER := Color("#e8953a")
const RED := Color("#ff7d6e")
const GREEN := Color("#8fb85a")
const BLUE := Color("#7fa6c9")
const GOLD := Color("#f0c24a")
const INK := Color("#eeeadd")
const INK2 := Color("#c1c5b5")
const PILL := Color(0.043, 0.078, 0.067, 0.9)
const TRACK := Color(0.04, 0.07, 0.06, 0.55)

## How the lists are refreshed (seconds of the screen's clock): the rules change them on a slow look, a person's walking to the place and back is the
## only thing that moves faster, and the words under a pill do not need it.
const REFRESH_MARKS := 0.25
const REFRESH_FACILITIES := 0.5
## How near the avatar has to be to a station (tiles) for its label to show without the Base page.
const FACILITY_NEAR := 12.0
## The sizes of the marks in pixels: the ground ring (from the zoom, between the two), the badge, the thin ring round it, the words.
const RING_MIN := 16.0
const RING_MAX := 52.0
const BADGE_R := 11.0
const TIMER_R := 15.5
const LABEL_PX := 13
const PILL_H := 18.0
const PILL_PAD := 7.0
const PILL_MAX_W := 260.0
## How far outside the window a mark may be and still be drawn (its badge and words reach beyond its ground ring).
const CULL := Vector2(110.0, 110.0)
## The words of the kinds in a toast or an alert ("Trouble: the leak").
const NOUN := {"leak": "the leak", "jam": "the jammed generator", "quarrel": "the quarrel", "crack": "the cracked wall", "quarantine": "the quarantine"}
## The short names of the kinds (the list's rows, a tooltip).
const NAME := {"leak": "Leak", "jam": "Jam", "quarrel": "Quarrel", "crack": "Crack", "quarantine": "Quarantine"}

# The glyphs, in units of the badge's half size (a canvas transform scales them): a teardrop, a lightning bolt, a speech bubble with an angry stroke,
# a crack, a cross. Made once, when the script loads (a vector is not a constant expression): nothing is built at draw time.
static var DROP := PackedVector2Array([
	Vector2(0, -1.0), Vector2(0.25, -0.55), Vector2(0.55, -0.1), Vector2(0.68, 0.25), Vector2(0.55, 0.6), Vector2(0.28, 0.88),
	Vector2(0, 0.98), Vector2(-0.28, 0.88), Vector2(-0.55, 0.6), Vector2(-0.68, 0.25), Vector2(-0.55, -0.1), Vector2(-0.25, -0.55)])
static var BOLT := PackedVector2Array([
	Vector2(0.3, -1.0), Vector2(-0.5, 0.15), Vector2(-0.05, 0.15), Vector2(-0.3, 1.0), Vector2(0.5, -0.2), Vector2(0.05, -0.2)])
static var BUBBLE := PackedVector2Array([
	Vector2(-0.95, -0.7), Vector2(0.95, -0.7), Vector2(0.95, 0.3), Vector2(0.15, 0.3), Vector2(-0.4, 0.95), Vector2(-0.3, 0.3), Vector2(-0.95, 0.3)])
static var ANGRY := PackedVector2Array([Vector2(-0.6, -0.05), Vector2(-0.2, -0.45), Vector2(0.15, 0.05), Vector2(0.6, -0.4)])
static var CRACK := PackedVector2Array([Vector2(0.2, -1.0), Vector2(-0.3, -0.35), Vector2(0.25, 0.05), Vector2(-0.25, 0.6), Vector2(0.1, 1.0)])

## Whether a test is looking: what was drawn is kept in `tags` ({"what": "problem"|"facility"|"sub"|"quarantine"|"fix", "id", "kind", "text", "color", "rect"}).
var record := false
var tags: Array = []
## What the last `draw` put on the screen (the counters the overlay passes on to the tests).
var drawn_marks := 0
var drawn_labels := 0
var drawn_facilities := 0
var drawn_quarantine := 0
var fix_ring := false
var fix_progress := 0.0
var fix_left := 0.0

var _marks: Array = []
var _facs: Array = []
var _t_marks := -1.0e9
var _t_facs := -1.0e9
var _fix_id := ""
var _fix_total := 0.0
var _widths := {}
var _widths_small := {}
var _fix_secs := -1
var _fix_text := ""
var _sb := StyleBoxFlat.new()
var _label_font: Font = null
var _small_font: Font = null
var _covered: Array = []
var _covered_asked := false


func _init() -> void:
	_sb.set_corner_radius_all(9)
	_sb.set_border_width_all(1)
	_sb.anti_aliasing = true


## Forgets what the lists said at the last look, so that the next draw asks again (a test that changed the game asks for it).
func forget() -> void:
	_t_marks = -1.0e9
	_t_facs = -1.0e9


## Nothing drawn (the counters of a frame in which the marks are not to be shown).
func clear() -> void:
	drawn_marks = 0
	drawn_labels = 0
	drawn_facilities = 0
	drawn_quarantine = 0
	fix_ring = false
	fix_progress = 0.0
	fix_left = 0.0
	tags.clear()


# ----------------------------------------------------------------- the glyphs --

## The words of a kind in a sentence ("the leak"; the kind itself when it is not one of ours).
static func noun(kind: String) -> String:
	return String(NOUN.get(kind, kind))


## The short name of a kind ("Leak").
static func name_of(kind: String) -> String:
	return String(NAME.get(kind, kind.capitalize()))


## The colour of a problem by how far it has come: amber while it is open (stage 0 and 1), red at stage 2 and once its time is used.
static func stage_color(stage: int, pct: float) -> Color:
	return RED if stage >= 2 or pct >= 1.0 else AMBER


## A glyph of `kind` ("leak", "jam", "quarrel", "crack", "quarantine") centred at `c` and `s` pixels from its centre to its edge, in `col`; `ink` is what
## is cut out of it (the stroke inside the bubble). Works in whatever canvas it is given (the world's overlay, a list row).
static func glyph(canvas: CanvasItem, kind: String, c: Vector2, s: float, col: Color, ink: Color = PILL) -> void:
	canvas.draw_set_transform(c, 0.0, Vector2(s, s))
	var w := 2.4 / maxf(s, 1.0)    # (a stroke 2.4 px wide, in the units of the glyph)
	match kind:
		"leak":
			canvas.draw_colored_polygon(DROP, col)
		"jam":
			canvas.draw_colored_polygon(BOLT, col)
		"quarrel":
			canvas.draw_colored_polygon(BUBBLE, col)
			canvas.draw_polyline(ANGRY, ink, w, true)
		"crack":
			canvas.draw_polyline(CRACK, col, w * 1.3, true)
		_:
			canvas.draw_rect(Rect2(-1.0, -0.3, 2.0, 0.6), col)
			canvas.draw_rect(Rect2(-0.3, -1.0, 0.6, 2.0), col)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------- the draw --

## Puts the marks on `canvas` (the overlay, inside its `_draw`). `to_screen`: Callable(tiles Vector2) -> pixels Vector2. `opts`: "z" (pixels a tile is),
## "vp" (the window's size), "clock" (the screen's clock in seconds: the pulse and the refresh), "calm" (reduced motion: steady marks), "me" (the avatar's
## place in tiles as drawn, Vector2.INF with none), "base_page" (the Base page is open: every station's label shows) and "covered" (a Callable returning
## the rectangles of the HUD's boards over the world; the words keep clear of them).
func draw(canvas: CanvasItem, sim, to_screen: Callable, opts: Dictionary) -> void:
	clear()
	if sim == null:
		return
	var now := float(opts.get("clock", 0.0))
	var z := float(opts.get("z", 40.0))
	var vp: Vector2 = opts.get("vp", Vector2(1280, 800))
	var calm := bool(opts.get("calm", false))
	var me: Vector2 = opts.get("me", Vector2.INF)
	var view := Rect2(-CULL, vp + CULL * 2.0)
	_covered_asked = false
	_refresh_marks(sim, now)
	_refresh_facilities(sim, now)
	if _label_font == null:
		_label_font = Fonts.cond(700)
		_small_font = Fonts.sans(600)
	# the stations that wait on something: under the rest
	if not _facs.is_empty():
		var all: bool = bool(opts.get("base_page", false))
		for f in _facs:
			var pos: Vector2 = f.pos
			if not all and (me == Vector2.INF or me.distance_to(pos) > FACILITY_NEAR):
				continue
			var c: Vector2 = to_screen.call(pos)
			if not view.has_point(c):
				continue
			_facility(canvas, f, c, z, vp, opts)
	# the trouble and the sign
	for m in _marks:
		var c: Vector2 = to_screen.call(m.at)
		if not view.has_point(c):
			continue
		_mark(canvas, m, c, z, vp, now, calm, opts)
	_fix(canvas, sim, to_screen, me, z, vp, opts)


## The words of the rules for the places where the marks are (asked a few times a second).
func _refresh_marks(sim, now: float) -> void:
	if now >= _t_marks and now - _t_marks < REFRESH_MARKS:
		return
	_t_marks = now
	_marks.clear()
	var pm = sim.get("problems")
	if pm != null and pm.has_method("marks"):
		var raw = pm.marks()
		if raw is Array:
			for m in raw:
				if m is Dictionary and m.get("at") is Vector2:
					var e: Dictionary = (m as Dictionary).duplicate()
					e["kind"] = String(e.get("kind", "leak"))
					e["sub"] = _who_is_on_it(sim, pm, e)
					_marks.append(e)
	var dm = sim.get("dilemmas")
	if dm != null and dm.has_method("marks"):
		var raw2 = dm.marks()
		if raw2 is Array:
			for m in raw2:
				if m is Dictionary and m.get("at") is Vector2:
					var e2: Dictionary = (m as Dictionary).duplicate()
					e2["kind"] = String(e2.get("kind", "quarantine"))
					e2["sub"] = ""
					_marks.append(e2)


func _refresh_facilities(sim, now: float) -> void:
	if now >= _t_facs and now - _t_facs < REFRESH_FACILITIES:
		return
	_t_facs = now
	_facs.clear()
	var bm = sim.get("briefing")
	if bm == null or not bm.has_method("facilities"):
		return
	var raw = bm.facilities()
	if not (raw is Array):
		return
	for f in raw:
		if f is Dictionary and not bool(f.get("ok", true)) and f.get("pos") is Vector2 and String(f.get("line", "")) != "":
			_facs.append(f)


## "Dez is on the way" / "Dez is fixing it" for a problem somebody else has been sent to ("" when nobody is, or when it is the avatar's own hands).
func _who_is_on_it(sim, pm, m: Dictionary) -> String:
	var state := String(m.get("state", "idle"))
	if state != "walking" and state != "working":
		return ""
	var fixing = pm.get("fixing")
	if fixing is Dictionary and String(fixing.get("id", "")) == String(m.get("id", "")):
		return ""
	var fixer := String(m.get("fixer", ""))
	if fixer == "" and not m.has("fixer") and pm.has_method("record"):
		var rec = pm.record(m.get("id", ""))
		fixer = String(rec.get("fixer", "")) if rec is Dictionary else ""
	if fixer == "":
		return ""
	for p in sim.people:
		if String(p.id) == fixer:
			return "%s is %s" % [String(p.first), "on the way" if state == "walking" else "fixing it"]
	return ""


# ----------------------------------------------------------------- the pieces --

func _width(font: Font, text: String, px: int) -> float:
	var table: Dictionary = _widths if font == _label_font else _widths_small
	var w = table.get(text)
	if w == null:
		if table.size() > 96:
			table.clear()
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		table[text] = w
	return float(w)


## The rectangles of the HUD's boards over the world, asked once a frame and only when there is a word to place.
func _boards(opts: Dictionary) -> Array:
	if not _covered_asked:
		_covered_asked = true
		_covered = []
		var g = opts.get("covered")
		if g is Callable and (g as Callable).is_valid():
			var got = (g as Callable).call()
			if got is Array:
				_covered = got
	return _covered


## A word on a dark pill (a rounded box of the slate, with an edge in `edge`) whose middle is at `at`: kept inside the window, off the HUD's boards.
## False (nothing drawn) when there is no such place.
func _pill(canvas: CanvasItem, text: String, at: Vector2, font: Font, px: int, ink: Color, edge: Color, vp: Vector2, opts: Dictionary) -> Rect2:
	var w := minf(_width(font, text, px), PILL_MAX_W) + PILL_PAD * 2.0
	var rect := Rect2(at.x - w * 0.5, at.y - PILL_H * 0.5, w, PILL_H)
	if not Rect2(4.0, 4.0, vp.x - 8.0, vp.y - 8.0).encloses(rect):
		return Rect2()
	for r in _boards(opts):
		if (r as Rect2).intersects(rect):
			return Rect2()
	_sb.bg_color = PILL
	_sb.border_color = Color(edge, 0.85)
	canvas.draw_style_box(_sb, rect)
	canvas.draw_string(font, Vector2(rect.position.x + PILL_PAD, rect.position.y + PILL_H * 0.5 + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, PILL_MAX_W, px, ink)
	return rect


## One trouble (or the sign of a quarantine): the ground ring, the badge with its glyph and its ring of time, the words, and who is on it.
func _mark(canvas: CanvasItem, m: Dictionary, c: Vector2, z: float, vp: Vector2, now: float, calm: bool, opts: Dictionary) -> void:
	var kind := String(m.kind)
	var sign_only := kind == "quarantine"
	var stage := int(m.get("stage", 0))
	var pct := clampf(float(m.get("pct", 0.0)), 0.0, 1.0)
	var col: Color = BLUE if sign_only else stage_color(stage, pct)
	var hot: bool = not sign_only and (stage >= 2 or pct >= 1.0)
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(now * (5.5 if hot else 3.2))
	var r := clampf(z * 0.75, RING_MIN, RING_MAX)
	# the ring on the ground, pulsing: a dark underlay, the colour, and a halo that opens and fades
	canvas.draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	canvas.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, TRACK, 5.0, true)
	canvas.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(col, 0.55 + 0.4 * pulse), 3.0, true)
	if not calm:
		canvas.draw_arc(Vector2.ZERO, r + 3.0 + 7.0 * pulse, 0.0, TAU, 32, Color(col, 0.5 * (1.0 - pulse)), 2.0, true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the badge over it, with the time that is left as a thin ring round it
	var b := Vector2(c.x, c.y - r * 0.5 - BADGE_R - 9.0)
	canvas.draw_circle(b, BADGE_R, PILL)
	canvas.draw_arc(b, BADGE_R, 0.0, TAU, 24, Color(col, 0.9), 1.5, true)
	glyph(canvas, kind, b, BADGE_R * 0.58, col)
	if not sign_only and m.has("pct"):
		canvas.draw_arc(b, TIMER_R, 0.0, TAU, 32, TRACK, 2.5, true)
		if pct < 1.0:
			canvas.draw_arc(b, TIMER_R, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - pct), 32, col, 2.5, true)
	drawn_marks += 1
	if sign_only:
		drawn_quarantine += 1
	# the rules' words over it
	var text := String(m.get("label", ""))
	if text != "":
		var rect := _pill(canvas, text, Vector2(c.x, b.y - TIMER_R - PILL_H * 0.5 - 3.0), _label_font, LABEL_PX, RED if hot else INK, col, vp, opts)
		if rect.size != Vector2.ZERO:
			drawn_labels += 1
			if record:
				tags.append({"what": "quarantine" if sign_only else "problem", "id": String(m.get("id", "")), "kind": kind, "text": text, "color": col, "rect": rect, "stage": stage})
	# who has been sent
	var sub := String(m.get("sub", ""))
	if sub != "":
		var rect2 := _pill(canvas, sub, Vector2(c.x, c.y + r * 0.5 + PILL_H * 0.5 + 4.0), _small_font, LABEL_PX, GREEN, GREEN, vp, opts)
		if record and rect2.size != Vector2.ZERO:
			tags.append({"what": "sub", "id": String(m.get("id", "")), "kind": kind, "text": sub, "color": GREEN, "rect": rect2})


## A station that waits on something: a small amber dot and the rules' line in a pill over the building.
func _facility(canvas: CanvasItem, f: Dictionary, c: Vector2, z: float, vp: Vector2, opts: Dictionary) -> void:
	var text := String(f.get("line", ""))
	var rect := _pill(canvas, text, Vector2(c.x, c.y - clampf(z * 1.1, 26.0, 72.0)), _small_font, LABEL_PX, INK2, AMBER, vp, opts)
	if rect.size == Vector2.ZERO:
		return
	canvas.draw_circle(Vector2(rect.position.x - 1.0, rect.position.y + PILL_H * 0.5), 3.5, AMBER)
	drawn_facilities += 1
	if record:
		tags.append({"what": "facility", "id": String(f.get("id", "")), "kind": "facility", "text": text, "color": AMBER, "rect": rect})


## The ring round the avatar's body while their hands are at a problem: it fills as the work goes (the bench's ring; `fixing.total` says how long the
## whole of it is, if the rules say so, else the first `left` that was seen).
func _fix(canvas: CanvasItem, sim, to_screen: Callable, me: Vector2, z: float, vp: Vector2, opts: Dictionary) -> void:
	var pm = sim.get("problems")
	var fixing = pm.get("fixing") if pm != null else null
	if not (fixing is Dictionary) or (fixing as Dictionary).is_empty() or me == Vector2.INF:
		_fix_id = ""
		return
	var left := maxf(0.0, float(fixing.get("left", 0.0)))
	var id := String(fixing.get("id", ""))
	if id != _fix_id:
		_fix_id = id
		_fix_total = 0.0
	_fix_total = maxf(_fix_total, maxf(left, float(fixing.get("total", 0.0))))
	fix_progress = clampf(1.0 - left / maxf(_fix_total, 0.01), 0.0, 1.0)
	fix_left = left
	var body: Vector2 = to_screen.call(me) + Vector2(0.0, -0.45 * z)
	var r := maxf(22.0, 0.74 * z)
	canvas.draw_arc(body, r, 0.0, TAU, 40, TRACK, 5.0, true)
	canvas.draw_arc(body, r, -PI / 2.0, -PI / 2.0 + fix_progress * TAU, 40, GOLD, 3.5, true)
	var secs := ceili(left)
	if secs != _fix_secs:
		_fix_secs = secs
		_fix_text = "Fixing %ds" % secs
	var text := _fix_text
	var rect := _pill(canvas, text, body + Vector2(0.0, r + 15.0), _label_font, LABEL_PX, GOLD, GOLD, vp, opts)
	fix_ring = true
	if record:
		tags.append({"what": "fix", "id": id, "kind": "fix", "text": text, "color": GOLD, "rect": rect})
