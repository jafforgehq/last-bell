## What the raid draws over its world, at screen size (round 14, R14.3): the exit's outline, a mark on each container
## (a ring while it is still to search, a progress ring while someone searches it, a tick once it is looted), the
## selection's brackets and rings under the squad, a name and a health bar under each of them, a red mark over the
## dead who hunt, the marks of the orders, the box being dragged, and a tag on what the pointer is over. All of it is a
## view: nothing here changes the rules. Lives on a CanvasLayer of the scene (raid_scene.gd), which it reads.
extends Node2D

const Fonts := preload("res://scripts/ui/fonts.gd")
const S := preload("res://scripts/render/shapes.gd")
const Hud := preload("res://scripts/ui/hud.gd")

const ACCENT := Color(0.941, 0.761, 0.29)
const INK := Color("#eeeadd")
const PILL := Color(11 / 255.0, 20 / 255.0, 17 / 255.0, 0.8)
const OK := Color("#8fb85a")
const INFO := Color("#7fa6c9")
const DANGER := Color("#e0584a")
## Nothing is drawn smaller than the HUD's floor for text.
const NAME_PX := 13

var scene
## What the last draw put on the screen (for the tests).
var drawn_containers := 0
var drawn_names := 0
var drawn_hunters := 0


func _pill(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, rect.size.y * 0.5, 5), color)


func _dashed_circle(c: Vector2, r: float, color: Color, width: float) -> void:
	var n := maxi(12, int(TAU * r / 10.0))
	for i in n:
		var a0 := TAU * i / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.4, 4, color, width, true)


func _dashed_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dist := a.distance_to(b)
	var t := 0.0
	while t < dist:
		var t1 := minf(dist, t + 6.0)
		draw_line(a.lerp(b, t / dist), a.lerp(b, t1 / dist), color, width, true)
		t += 11.0


## A word on a dark pill, centred at `c`.
func _tag(c: Vector2, text: String, font: Font, color: Color, back: Color = PILL) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_PX).x + 12.0
	_pill(Rect2(c.x - tw / 2.0, c.y - 9.0, tw, 18.0), back)
	draw_string(font, Vector2(c.x - tw / 2.0, c.y + NAME_PX * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, tw, NAME_PX, color)


func _draw() -> void:
	if scene == null or scene.run == null:
		return
	var run = scene.run
	var z: float = scene.zoom_px
	var vp := get_viewport_rect().size
	var screen := Rect2(Vector2(-60, -60), vp + Vector2(120, 120))
	var font := Fonts.cond(600)
	drawn_containers = 0
	drawn_names = 0
	drawn_hunters = 0

	# the way out: a dashed outline, so the squad knows where "back" is
	var ex: Rect2 = run.site.exit
	var a: Vector2 = scene.to_screen(ex.position)
	var b: Vector2 = scene.to_screen(ex.end)
	var lit: bool = run.phase == "retreat"
	var ex_col := Color(OK, 0.95 if lit else 0.55)
	for edge in [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b], [b, Vector2(a.x, b.y)], [Vector2(a.x, b.y), a]]:
		_dashed_line(edge[0], edge[1], ex_col, 2.0 if lit else 1.5)
	if screen.has_point(a):
		_tag(a + Vector2(30.0, -12.0), "Exit", font, INK, Color(OK.darkened(0.55), 0.9))

	# the containers
	for c in run.containers:
		var at: Vector2 = scene.to_screen(Vector2(c.at))
		if not screen.has_point(at):
			continue
		drawn_containers += 1
		var r := clampf(0.55 * z, 9.0, 40.0)
		if bool(c.looted):
			draw_circle(at, 9.0, Color(PILL, 0.85))
			draw_polyline(PackedVector2Array([at + Vector2(-4.5, 0.5), at + Vector2(-1.5, 3.8), at + Vector2(5.0, -4.0)]), OK, 2.5, true)
			continue
		var progress := float(c.progress) / maxf(float(c.search_s), 0.1)
		if progress > 0.0:
			draw_arc(at, r, 0, TAU, 32, Color(PILL, 0.8), 5.0, true)
			draw_arc(at, r, -PI / 2.0, -PI / 2.0 + progress * TAU, 32, ACCENT, 3.5, true)
		else:
			_dashed_circle(at, r, Color(ACCENT, 0.85), 2.0)

	# the squad: a ring under each, brackets and the reach round the selected
	var sel: Array = scene.selection
	for p in run.squad:
		if p.dead:
			continue
		var pp: Vector2 = scene.view_pos(p)
		var foot: Vector2 = scene.to_screen(pp)
		var chosen: bool = sel.has(p)
		var rw := 0.42 * z
		draw_set_transform(foot, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, rw, 0, TAU, 28, ACCENT if chosen else Color(INK, 0.45), 2.5 if chosen else 1.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if chosen:
			var ta: Vector2 = scene.to_screen(Vector2(pp.x - 0.48, pp.y - 0.92))
			var tb: Vector2 = scene.to_screen(Vector2(pp.x + 0.48, pp.y + 0.42))
			var L := maxf(5.0, (tb.x - ta.x) * 0.22)
			for k in [[ta.x, ta.y, 1, 1], [tb.x, ta.y, -1, 1], [ta.x, tb.y, 1, -1], [tb.x, tb.y, -1, -1]]:
				draw_polyline(PackedVector2Array([Vector2(k[0] + k[2] * L, k[1]), Vector2(k[0], k[1]), Vector2(k[0], k[1] + k[3] * L)]), ACCENT, 2.0, true)
			if not p.downed and sel.size() == 1:
				_dashed_circle(foot, run.sim.reach_of(p.gun, p) * z, Color(ACCENT, 0.28), 1.2)

	# the dead who hunt
	for zb in run.sim.zombies:
		if zb.state != "hunt":
			continue
		var head: Vector2 = scene.to_screen(scene.view_pos(zb) + Vector2(0.0, -1.15 * maxf(1.0, float(zb.size))))
		if not screen.has_point(head):
			continue
		drawn_hunters += 1
		draw_circle(head, 8.0, Color(DANGER, 0.92))
		draw_string(font, Vector2(head.x - 3.0, head.y + 5.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 6.0, NAME_PX, Color("#fff4ee"))

	# the marks of the orders
	for m in scene.marks:
		var k: float = (scene.clock - float(m.t)) / scene.MARK_S
		var col := ACCENT if m.kind == "move" else (OK if m.kind == "search" else INFO)
		draw_arc(scene.to_screen(Vector2(m.x, m.y)), (0.2 + k * 0.55) * z, 0, TAU, 32, Color(col, 1.0 - k), 2.5, true)

	# names and health under the squad
	if z >= 14.0:
		for p in run.squad:
			var pp: Vector2 = scene.view_pos(p)
			var pos: Vector2 = scene.to_screen(Vector2(pp.x, pp.y + 0.52))
			if not screen.has_point(pos):
				continue
			drawn_names += 1
			var chosen: bool = sel.has(p)
			var label: String = p.first
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_PX).x + 10.0
			var bg := Color(ACCENT, 0.92) if chosen else (Color(12 / 255.0, 22 / 255.0, 19 / 255.0, 0.74))
			_pill(Rect2(pos.x - tw / 2.0, pos.y - 9.0, tw, 18.0), bg)
			draw_string(font, Vector2(pos.x - tw / 2.0, pos.y + NAME_PX * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, tw, NAME_PX, Color("#1a1508") if chosen else INK)
			if p.hp < 100.0 and not p.dead:
				draw_rect(Rect2(pos.x - 14, pos.y + 11, 28, 4), PILL)
				draw_rect(Rect2(pos.x - 13.5, pos.y + 11.5, 27.0 * clampf(p.hp / 100.0, 0.0, 1.0), 3), Color("#d0493a") if p.hp < 35.0 else Color("#8fb85a"))

	# what the pointer is over
	var hv = scene.hover
	if hv != null and scene.drag == null:
		if hv.kind == "container":
			var c: Dictionary = hv.ref
			var at: Vector2 = scene.to_screen(Vector2(c.at))
			_tag(at + Vector2(0.0, -0.7 * z - 8.0), "%s: %d s to search" % [String(c.kind).capitalize(), int(ceilf(float(c.search_s)))], font, INK)
		elif hv.kind == "person":
			var p = hv.ref
			var pp: Vector2 = scene.view_pos(p)
			var ha: Vector2 = scene.to_screen(Vector2(pp.x - 0.45, pp.y - 0.88))
			draw_rect(Rect2(ha, Vector2(0.9, 1.28) * z), Color(1, 1, 1, 0.35), false, 1.0)

	# the box being dragged
	var d = scene.drag
	if d != null and d.moved and d.button == MOUSE_BUTTON_LEFT:
		draw_rect(d.box, Color(ACCENT, 0.12))
		draw_rect(d.box, Color(ACCENT, 0.85), false, 1.5)
