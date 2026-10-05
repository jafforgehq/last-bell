## The plan of the base (One House, WP7): a top-down drawing of the claimed house's lot with the house in it and every section the Build page's projects are made of,
## coloured by what it is now (locked, open, ordered, going up, built, broken). The sections are drawn small and plain: what the plan is for is to show WHERE a project
## goes. The project that is under the pointer (on the plan or on the page: `hover_project`), or else the one that is picked (`selected_project`), is lit: its sections
## are drawn in full, with a gold ring and its name; the rest of the plan is dimmed. A click on a section picks its project (`picked(project_id)`), a pointer over one
## says which it is (`hovered(project_id)`; "" when it leaves). Everything is in tiles of the lot; the drawing is scaled to fit its box.
##
##   var plan := SlotPlan.new(); plan.setup(hud)
##   plan.set_data({"lot": Rect2i, "house": Rect2i, "front": "N" or "S", "slots": [{"id", "kind", "rect", "state", "project", "project_name"}...], "posts": [Vector2...]})
##   plan.selected_project = "front"   # the gold rings
##
## A slot's "rect" is a Rect2i (or a Rect2, or {"position", "size"}) in map tiles. Read only: the plan changes nothing in the rules.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")

signal picked(project_id: String)
signal hovered(project_id: String)

const STATE_COLOR := {
	"locked": Color("#a8ae9d"),
	"open": Color("#f0c24a"),
	"ordered": Color("#7fa6c9"),
	"building": Color("#e8953a"),
	"built": Color("#8fb85a"),
	"broken": Color("#e0584a"),
}
const GROUND := Color(0.105, 0.17, 0.14, 1.0)
const GROUND_LINE := Color(0.93, 0.96, 0.89, 0.06)
const LOT_LINE := Color(0.93, 0.96, 0.89, 0.34)
const HOUSE_FILL := Color("#56391f")
const HOUSE_EDGE := Color("#8a6238")
const ROOF_LINE := Color(0.0, 0.0, 0.0, 0.22)
## The least a marker is drawn, and picked, in pixels: a fence of one tile is a thin bar, not a hair.
const MIN_MARK := 7.0
const PICK_PAD := 6.0
const MARGIN := 1.5
## How much of a section's colour is left when another project is the lit one.
const DIM := 0.3

var host
var lot := Rect2()
var house := Rect2()
var front := "S"
var slots: Array = []
var posts: Array = []
## The project that is picked, the one under the pointer on the plan (the plan sets it) and the one under the pointer on the page (the page does).
var selected_project := ""
var hover_project := ""
var card_hover := ""
## id -> the Rect2 of the marker on the screen at the last draw (what a click is tested against; the tests read it).
var marks := {}


func setup(host_hud) -> void:
	host = host_hud
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 168)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_ARROW


## The plan's content (see the header); a Rect2i, a Rect2 or {"position": .., "size": ..} for each rectangle.
func set_data(d: Dictionary) -> void:
	lot = to_rect(d.get("lot"))
	house = to_rect(d.get("house"))
	front = String(d.get("front", "S"))
	slots = d.get("slots", [])
	posts = d.get("posts", [])
	queue_redraw()


static func to_rect(v) -> Rect2:
	if v is Rect2i:
		return Rect2(v)
	if v is Rect2:
		return v
	if v is Dictionary and v.has("position") and v.has("size"):
		var p = v.position
		var s = v.size
		return Rect2(float(p.x), float(p.y), float(s.x), float(s.y))
	return Rect2()


## The project that is lit now ("" for none: every section is drawn in full).
func lit() -> String:
	if hover_project != "":
		return hover_project
	return card_hover if card_hover != "" else selected_project


## What the drawing covers: the lot with a margin, or the slots' own extent when there is no lot.
func _world() -> Rect2:
	var r := lot
	if r.size == Vector2.ZERO:
		r = house
	for s in slots:
		var sr := to_rect(s.get("rect"))
		r = sr if r.size == Vector2.ZERO else r.merge(sr)
	return r.grow(MARGIN)


## Where the tile rectangle `r` is on the screen for the world `w` fitted into this control.
func _fit(w: Rect2) -> Dictionary:
	var k := minf(size.x / maxf(w.size.x, 1.0), size.y / maxf(w.size.y, 1.0))
	var origin := (size - w.size * k) * 0.5
	return {"k": k, "origin": origin, "w": w}


func _px(f: Dictionary, r: Rect2) -> Rect2:
	var w: Rect2 = f.w
	return Rect2(f.origin + (r.position - w.position) * float(f.k), r.size * float(f.k))


func _draw() -> void:
	marks.clear()
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	var w := _world()
	if w.size == Vector2.ZERO or host == null:
		return
	var f := _fit(w)
	var k: float = f.k
	# a faint tile grid, so that the scale reads
	var x0 := ceilf(w.position.x)
	while x0 < w.end.x:
		var a: Vector2 = _px(f, Rect2(x0, w.position.y, 0, w.size.y)).position
		draw_line(a, a + Vector2(0, w.size.y * k), GROUND_LINE, 1.0)
		x0 += 1.0
	var y0 := ceilf(w.position.y)
	while y0 < w.end.y:
		var b: Vector2 = _px(f, Rect2(w.position.x, y0, w.size.x, 0)).position
		draw_line(b, b + Vector2(w.size.x * k, 0), GROUND_LINE, 1.0)
		y0 += 1.0
	if lot.size != Vector2.ZERO:
		_dashed_rect(_px(f, lot), LOT_LINE)
	if house.size != Vector2.ZERO:
		var hr := _px(f, house)
		draw_rect(hr, HOUSE_FILL)
		draw_rect(hr, HOUSE_EDGE, false, 2.0)
		# the roof's ridge, and the front door on the side the house faces
		draw_line(hr.position + Vector2(hr.size.x * 0.5, 3.0), hr.position + Vector2(hr.size.x * 0.5, hr.size.y - 3.0), ROOF_LINE, 2.0)
		var door := Rect2(hr.position.x + hr.size.x * 0.5 - 7.0, (hr.end.y - 3.0) if front == "S" else (hr.position.y - 2.0), 14.0, 5.0)
		draw_rect(door, Color(host.ACCENT, 0.9))
		var font := Fonts.cond(700)
		draw_string(font, hr.position + Vector2(0, hr.size.y * 0.5 + 5.0), "HOUSE", HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 14, Color(host.INK, 0.8))
	for p in posts:
		if p is Vector2:
			var pp: Vector2 = _px(f, Rect2(p, Vector2.ZERO)).position
			draw_circle(pp, 2.0, Color(host.INK3, 0.5))
	var on := lit()
	var name_at := Vector2.ZERO
	var lit_name := ""
	for s in slots:
		_mark(f, s, on)
		if on != "" and String(s.get("project", "")) == on and lit_name == "":
			lit_name = String(s.get("project_name", ""))
	# the lit project's name, in a corner
	if lit_name != "":
		name_at = Vector2(8.0, size.y - 8.0)
		draw_string(Fonts.cond(700), name_at, lit_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 40.0, 14, Color(host.ACCENT, 1.0))
	# north is up
	draw_string(Fonts.cond(700), Vector2(size.x - 18.0, 16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(host.INK3, 0.9))


func _mark(f: Dictionary, s: Dictionary, on: String) -> void:
	var id := String(s.get("id", ""))
	var kind := String(s.get("kind", "fence"))
	var state := String(s.get("state", "open"))
	var project := String(s.get("project", ""))
	var col: Color = STATE_COLOR.get(state, host.INK3)
	var r := _px(f, to_rect(s.get("rect")))
	# a thin fence is drawn at least MIN_MARK across, round its middle
	var mid := r.get_center()
	var shown := Rect2(mid - Vector2(maxf(r.size.x, MIN_MARK), maxf(r.size.y, MIN_MARK)) * 0.5, Vector2(maxf(r.size.x, MIN_MARK), maxf(r.size.y, MIN_MARK)))
	marks[id] = shown
	var is_lit := on != "" and project == on
	var fade := 1.0 if (on == "" or is_lit) else DIM
	var fill := Color(col, (0.28 if state != "built" else 0.55) * fade)
	var edge := Color(col, (1.0 if state != "locked" else 0.7) * fade)
	match kind:
		"floodlight":
			var c := shown.get_center()
			var rad := maxf(shown.size.x, shown.size.y) * 0.5 + 2.0
			draw_circle(c, rad, fill)
			draw_arc(c, rad, 0.0, TAU, 20, edge, 2.0, true)
			for i in 4:
				var d := Vector2.from_angle(i * PI * 0.5 + PI * 0.25)
				draw_line(c + d * (rad + 2.0), c + d * (rad + 6.0), edge, 1.5)
		"tower":
			var t := shown.grow(2.0)
			draw_rect(t, fill)
			draw_rect(t, edge, false, 2.0)
			draw_line(t.position, t.end, Color(edge, 0.8 * fade), 1.5)
			draw_line(Vector2(t.end.x, t.position.y), Vector2(t.position.x, t.end.y), Color(edge, 0.8 * fade), 1.5)
		"gate":
			draw_rect(shown, fill)
			draw_rect(shown, edge, false, 2.0)
			var horizontal := shown.size.x >= shown.size.y
			if horizontal:
				draw_line(Vector2(mid.x, shown.position.y), Vector2(mid.x, shown.end.y), edge, 2.0)
			else:
				draw_line(Vector2(shown.position.x, mid.y), Vector2(shown.end.x, mid.y), edge, 2.0)
		_:
			draw_rect(shown, fill)
			draw_rect(shown, edge, false, 2.0)
	if state == "locked":
		# a locked slot is struck through
		draw_line(shown.position + Vector2(2, 2), shown.end - Vector2(2, 2), Color(col, 0.55 * fade), 1.5)
	if is_lit:
		draw_rect(shown.grow(4.0), Color(host.ACCENT, 1.0 if (project == hover_project or project == card_hover or project == selected_project) else 0.7), false, 2.0)


func _dashed_rect(r: Rect2, color: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(2, int(a.distance_to(b) / 10.0))
		for j in n:
			if j % 2 == 0:
				draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), color, 1.5)


## The id of the slot whose marker is nearest the point (within PICK_PAD of it), or "".
func slot_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in marks:
		var r: Rect2 = (marks[id] as Rect2).grow(PICK_PAD)
		if not r.has_point(p):
			continue
		var d := (marks[id] as Rect2).get_center().distance_to(p)
		if d < best_d:
			best_d = d
			best = String(id)
	return best


## The project of the section under the point ("" when there is none).
func project_at(p: Vector2) -> String:
	var id := slot_at(p)
	if id == "":
		return ""
	for s in slots:
		if String(s.get("id", "")) == id:
			return String(s.get("project", ""))
	return ""


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var pid := project_at((ev as InputEventMouseMotion).position)
		if pid != hover_project:
			hover_project = pid
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if pid != "" else Control.CURSOR_ARROW
			hovered.emit(pid)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var pid2 := project_at((ev as InputEventMouseButton).position)
		if pid2 != "":
			picked.emit(pid2)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover_project != "":
		hover_project = ""
		hovered.emit("")
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()
