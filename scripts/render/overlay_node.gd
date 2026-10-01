## In-world labels drawn at screen size: names under people, health and
## reload rings, wall damage bars, selection brackets, range circle and the
## move-order marker. And the night tools' drawings: the fields-of-fire view (key V:
## every wall section tinted by how many guns reach it, each gun's reach, and on the
## forecast night where the dead come in) and the marker of the alarm (the lure) on
## the wall section it rings at. And (round 4) what people say: speech bubbles over their heads.
## All of it is a view: nothing here changes the rules.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const S := preload("res://scripts/render/shapes.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Frames := preload("res://scripts/ui/frames.gd")
const Prefs := preload("res://scripts/prefs.gd")
const TILE := 64.0
const ACCENT := Color(0.941, 0.761, 0.29)
## The size of the names under people: the same floor as the HUD's text (Fonts.MIN_PX).
const NAME_PX := 12
## The tint of a wall section by how many guns reach it: none, one, two or more (the
## HUD's red, amber and green). A pale fill that leaves the wall's art showing, and an edge.
const COVER := [Color("#e0584a"), Color("#e8953a"), Color("#8fb85a")]
const COVER_FILL := 0.28
const COVER_EDGE := 0.9
## The reach of each gun at its post: a faint pale disc with a ring.
const REACH := Color(0.93, 0.9, 0.82)
const REACH_FILL := 0.07
const REACH_EDGE := 0.22
## Where the dead come in tonight (the forecast's main spawn points).
const SPAWN := Color("#e0584a")
const SPAWN_TEXT := Color("#ef6c5d")
## The alarm: the colour of the HUD's info (the alert says it in the same blue).
const ALARM := Color("#7fa6c9")
const INK := Color("#eeeadd")
## The size of the numbers and words of these drawings: not under the floor (Fonts.MIN_PX).
const FIELD_PX := 13
## The slate of the HUD's boards under a word or a bar in the world.
const PILL := Color(11 / 255.0, 20 / 255.0, 17 / 255.0, 0.8)
## Speech bubbles (round 4): what a person says (a `bark` event from the rules, passed on by main.gd's
## _handle_events to `add_bark`) shows for BUBBLE_SECONDS in a bubble above their head: the `bubble` frame
## of the HUD's paper (flat when the theme has none), in the HUD's font, in screen space (it does not grow
## with the world's zoom), kept BUBBLE_MARGIN inside the view, faded in and out and drifting up a little (not
## with reduced motion), at most BUBBLE_MAX at once, none while a modal is open or for someone off the screen.
const BUBBLE_FRAME_KIND := "bubble"
## The size of the words: the HUD's floor for text (Fonts.MIN_PX) or more.
const BUBBLE_PX := 13
const BUBBLE_SECONDS := 3.0
const BUBBLE_FADE_IN := 0.18
const BUBBLE_FADE_OUT := 0.5
## How far a bubble drifts up over its life, in pixels.
const BUBBLE_FLOAT := 7.0
const BUBBLE_MAX := 2
## The widest a line of words is before it wraps, and how far a bubble keeps in from the edge of the view.
const BUBBLE_MAX_W := 190.0
const BUBBLE_MARGIN := 8.0
## How far over the head the tail's tip is, and how high the head is above the feet, in tiles.
const BUBBLE_GAP := 3.0
const BUBBLE_HEAD := 0.95
## Where the tail's tip is when the frame does not say (frames.json "tail"): [from the bubble's left edge, below its foot].
const BUBBLE_TAIL := [8.5, 8.0]
## The way the dead face at a wall's attack places (towards the wall), as a step in tiles:
## a step the other way is out in front of the wall.
const FACE := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}

var main
## What the last draw put on the screen (for the tests: a section, a gun's reach or an arrow
## that is out of the window is not drawn, and does not count).
var drawn_sections := 0
var drawn_reach := 0
var drawn_spawns := 0
var drew_alarm := false
## What people are saying: [{"p": Person, "text", "born": main.clock}], the oldest first; and how many bubbles
## the last draw put on the screen.
var bubbles: Array = []
var drawn_bubbles := 0
var _bubble_sb: StyleBox = null
var _bubble_framed := false


func _screen(x: float, y: float) -> Vector2:
	return get_viewport().get_canvas_transform() * (Vector2(x, y) * TILE)


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


# ------------------------------------------------------ the night tools --

## The tint of a wall section reached by `n` guns: red for none, amber for one, green for more.
static func cover_color(n: int) -> Color:
	return COVER[clampi(n, 0, COVER.size() - 1)]


## A wall section's footprint in tiles: the box round its object, turned with it (the
## object's own rectangle is `w` by `h` at the angle `a`).
static func section_rect(seg) -> Rect2:
	var o: Dictionary = seg.obj
	var hw: float = absf(cos(o.a)) * o.w / 2.0 + absf(sin(o.a)) * o.h / 2.0
	var hh: float = absf(sin(o.a)) * o.w / 2.0 + absf(cos(o.a)) * o.h / 2.0
	return Rect2(o.cx - hw, o.cy - hh, hw * 2.0, hh * 2.0)


## Where the alarm's bell hangs for a section, in tiles: out in front of it, where the
## dead gather (the middle of its attack places, a step away from the wall).
static func alarm_anchor(seg) -> Vector2:
	if seg.slots.is_empty():
		return seg.center
	var mid := Vector2.ZERO
	for sl in seg.slots:
		mid += Vector2(sl.x, sl.y)
	mid /= float(seg.slots.size())
	var face: Vector2 = FACE.get(String(seg.slots[0].face), Vector2(0, 1))
	return mid - face * 1.2


## The way inward from a point on the map's edge (a step from the nearest edge to the middle).
static func inward(at: Vector2, w: float, h: float) -> Vector2:
	var best := at.x
	var dir := Vector2(1, 0)
	if w - at.x < best:
		best = w - at.x
		dir = Vector2(-1, 0)
	if at.y < best:
		best = at.y
		dir = Vector2(0, 1)
	if h - at.y < best:
		dir = Vector2(0, -1)
	return dir


## "2h 10m", or "45m" under an hour: the time the alarm has left, from game minutes.
static func time_text(minutes: float) -> String:
	var m := maxi(0, ceili(minutes))
	if m >= 60:
		return "%dh %02dm" % [int(m / 60.0), m % 60]
	return "%dm" % m


## What the fields-of-fire view shows, in tiles: {"sections": [{"id", "rect", "n" (guns
## that reach it), "color", "damaged"}], "reach": [{"id", "at", "r"}] (each gun at
## its post), "spawns": [{"at", "dir"}] (where the dead come in tonight, if the lookout
## has said)}. The rules' own numbers (sim.tactics), read and not changed.
func fields_plan(sim) -> Dictionary:
	var cover: Dictionary = sim.tactics.coverage_map()
	var sections: Array = []
	for s in sim.segments:
		var n: int = int(cover.get(s.id, 0))
		sections.append({"id": s.id, "rect": section_rect(s), "n": n, "color": cover_color(n), "damaged": s.hp < s.max_hp * 0.95})
	var reach: Array = []
	for p in sim.people:
		if p.dead or p.downed or p.away != null:
			continue
		reach.append({"id": p.id, "at": sim.tactics.post_pos(p), "r": float(p.gun.range)})
	var spawns: Array = []
	var f: Dictionary = sim.tactics.forecast()
	if bool(f.get("given", false)):
		for at in f.get("spawns", []):
			spawns.append({"at": at, "dir": inward(at, float(sim.W), float(sim.H))})
	return {"sections": sections, "reach": reach, "spawns": spawns}


func _icon(name: String) -> Texture2D:
	var path = GD.load_all().get("icons", {}).get(name)
	return GD.tex(String(path)) if path != null else null


## A pale disc with a ring: the reach of a gun.
func _disc(c: Vector2, r: float, fill: Color, edge: Color) -> void:
	var n := clampi(int(r / 3.0), 24, 120)
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, fill)
	draw_polyline(S.closed(pts), edge, 1.5, true)


## A word on a dark pill, centred at `c`, with a ring round the pill if `ring` is given.
func _tag(c: Vector2, text: String, font: Font, color: Color, back: Color = PILL, ring: Color = Color(0, 0, 0, 0)) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 10.0
	var box := Rect2(c.x - tw / 2.0, c.y - 8.0, tw, 16.0)
	_pill(box, back)
	if ring.a > 0.0:
		draw_polyline(S.closed(S.rrect(box.position.x, box.position.y, box.size.x, box.size.y, box.size.y * 0.5, 5)), ring, 1.5, true)
	draw_string(font, Vector2(c.x - tw / 2.0, c.y + FIELD_PX * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, tw, FIELD_PX, color)


## The fields-of-fire view: the reach of each gun (faint), then every wall section tinted
## by how many guns reach it with that number at its middle, then the arrows where the
## dead come in tonight.
func _draw_fields(sim, z: float, vp: Vector2) -> void:
	var plan := fields_plan(sim)
	var view := Rect2(-60.0, -60.0, vp.x + 120.0, vp.y + 120.0)
	for r in plan.reach:
		var c := _screen(r.at.x, r.at.y)
		var px: float = r.r * z
		if view.grow(px).has_point(c):
			_disc(c, px, Color(REACH, REACH_FILL), Color(REACH, REACH_EDGE))
			drawn_reach += 1
	var font := Fonts.cond(700)
	for item in plan.sections:
		var rect: Rect2 = item.rect
		var a := _screen(rect.position.x, rect.position.y)
		var b := _screen(rect.end.x, rect.end.y)
		var box := Rect2(a, b - a)
		if not box.intersects(view):
			continue
		drawn_sections += 1
		var col: Color = item.color
		draw_rect(box, Color(col, COVER_FILL))
		draw_rect(box, Color(col, COVER_EDGE), false, 1.5)
		# the number at the middle (above the damage bar, which is drawn there too)
		var mid := box.get_center() + Vector2(0.0, -11.0 if item.damaged else 0.0)
		_tag(mid, str(item.n), font, INK, Color(col.darkened(0.6), 0.92), Color(col, 0.95))
	for sp in plan.spawns:
		_draw_spawn(sp, z, font, vp)


## A pulsing red arrow at a spawn point on the map's edge, pointing inward, with "from here".
func _draw_spawn(sp: Dictionary, z: float, font: Font, vp: Vector2) -> void:
	var at := _screen(sp.at.x, sp.at.y)
	if at.x < -80.0 or at.y < -80.0 or at.x > vp.x + 80.0 or at.y > vp.y + 80.0:
		return
	drawn_spawns += 1
	var d: Vector2 = sp.dir
	var pulse := 0.5 + 0.5 * sin(float(main.clock) * 4.5)
	var length := clampf(z * 1.5, 24.0, 48.0)
	var xf := Transform2D(d.angle(), at + d * (length * 0.2 * pulse))
	var shaft := length * 0.2
	var wing := length * 0.46
	var head := length * 0.5
	var pts := PackedVector2Array([Vector2(0, -shaft), Vector2(length - head, -shaft), Vector2(length - head, -wing), Vector2(length, 0), Vector2(length - head, wing), Vector2(length - head, shaft), Vector2(0, shaft)])
	for i in pts.size():
		pts[i] = xf * pts[i]
	var alpha := 0.6 + 0.4 * pulse
	draw_colored_polygon(pts, Color(SPAWN, alpha))
	draw_polyline(S.closed(pts), Color(0.1, 0.05, 0.04, 0.85 * alpha), 1.5, true)
	# the words beyond the tip, further in along the arrow
	var tip: Vector2 = xf * Vector2(length, 0)
	var tw := font.get_string_size("from here", HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 10.0
	var out := tip + d * (8.0 + (tw / 2.0 if absf(d.x) > 0.5 else 8.0))
	_tag(out, "from here", font, SPAWN_TEXT)


## The alarm's marker on the section it rings at: a pulsing outline round the section, a bell
## swinging in front of it with rings spreading out, and the time it has left.
func _draw_alarm(sim, z: float, vp: Vector2) -> void:
	var seg = sim.tactics.lure_seg()
	if seg == null:
		return
	var t: float = main.clock
	var rect := section_rect(seg)
	var a := _screen(rect.position.x, rect.position.y)
	var b := _screen(rect.end.x, rect.end.y)
	var box := Rect2(a, b - a)
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	var view := Rect2(-80.0, -80.0, vp.x + 160.0, vp.y + 160.0)
	if box.intersects(view):
		draw_rect(box.grow(2.0 + pulse * 2.0), Color(ALARM, 0.45 + 0.4 * pulse), false, 2.0)
	var tile := alarm_anchor(seg)
	var c := _screen(tile.x, tile.y)
	if not view.has_point(c):
		return
	drew_alarm = true
	# rings spreading out like sound
	for i in 2:
		var k := fposmod(t * 0.8 + float(i) * 0.5, 1.0)
		draw_arc(c, lerpf(15.0, maxf(44.0, 2.2 * z), k), 0.0, TAU, 48, Color(ALARM, (1.0 - k) * 0.75), 2.0, true)
	draw_circle(c, 14.0, PILL)
	draw_arc(c, 14.0, 0.0, TAU, 32, ALARM, 2.0, true)
	var bell := _icon("bell")
	if bell != null:
		# the bell swings on its hook
		draw_set_transform(c, sin(t * 9.0) * 0.28, Vector2.ONE)
		draw_texture_rect(bell, Rect2(-8.0, -8.0, 16.0, 16.0), false, ALARM)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_tag(c + Vector2(0.0, 28.0), time_text(sim.tactics.lure_left_min()), Fonts.cond(700), ALARM)


# ------------------------------------------------------------- speech bubbles --

## A person said something (the `bark` event {"who": id, "text", "context"}): a bubble over their head.
## One a person (a new line takes the place of their old one) and BUBBLE_MAX at most (the oldest goes);
## none for the dead or the away and none is made while a modal is open.
func add_bark(e: Dictionary) -> void:
	if main == null or main.sim == null or _modal_open():
		return
	var text := String(e.get("text", "")).strip_edges()
	var who = _person(String(e.get("who", "")))
	if text == "" or who == null or who.dead or who.away != null:
		return
	for i in range(bubbles.size() - 1, -1, -1):
		if bubbles[i].p == who:
			bubbles.remove_at(i)
	bubbles.append({"p": who, "text": text, "born": float(main.clock)})
	while bubbles.size() > BUBBLE_MAX:
		bubbles.pop_front()


func _person(id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


## Whether a menu or the HUD's dialog is open over the game (the game's `menu_open`, the HUD's `modal_open`):
## main.gd and the HUD answer; a stand-in for either that has no such thing means none.
func _modal_open() -> bool:
	if main == null:
		return false
	if bool(main.get("menu_open")):
		return true
	var hud = main.get("hud")
	return hud != null and hud.has_method("modal_open") and bool(hud.modal_open())


## How solid a bubble is `age` seconds after it was said: it fades in and out, not with reduced motion.
static func bubble_alpha(age: float, calm: bool) -> float:
	if calm:
		return 1.0
	return clampf(minf(age / BUBBLE_FADE_IN, (BUBBLE_SECONDS - age) / BUBBLE_FADE_OUT), 0.0, 1.0)


## The look of a bubble: the `bubble` frame of the theme, else a flat sheet of paper. (Kept until the frames
## are switched on or off.)
func _bubble_box() -> StyleBox:
	var framed := Hud.has_frame(BUBBLE_FRAME_KIND)
	if _bubble_sb == null or framed != _bubble_framed:
		_bubble_framed = framed
		_bubble_sb = Hud.frame(BUBBLE_FRAME_KIND) if framed else null
		if _bubble_sb == null:
			var f := StyleBoxFlat.new()
			f.bg_color = Hud.PAPER
			f.border_color = Color(Hud.PAPER_INK, 0.55)
			f.set_border_width_all(1)
			f.set_corner_radius_all(5)
			f.anti_aliasing = true
			f.content_margin_left = 8
			f.content_margin_right = 8
			f.content_margin_top = 5
			f.content_margin_bottom = 6
			_bubble_sb = f
	return _bubble_sb


## [from the bubble's left edge, below its foot]: where the tail's tip is, from frames.json.
func _bubble_tail() -> Array:
	if Hud.has_frame(BUBBLE_FRAME_KIND):
		var t = Frames.info(BUBBLE_FRAME_KIND).get("tail")
		if t is Array and t.size() >= 2:
			return [float(t[0]), float(t[1])]
	return BUBBLE_TAIL


## What the bubbles look like now, for the window `vp` big: [{"who", "text", "lines", "size" (the words'
## pixel size), "rect" (the bubble's body, in screen pixels), "tip" (where its tail's tip is: over the
## speaker's head, unless the view's edge pushed the bubble aside), "flip" (the picture is mirrored, the tail
## at the right), "alpha", "framed"}]. A bubble that has had its time is forgotten here. None while a modal is
## open, and none for a speaker who is gone, away or off the screen.
func bubble_plan(vp: Vector2) -> Array:
	var plan: Array = []
	if main == null or main.sim == null:
		return plan
	var now: float = main.clock
	for i in range(bubbles.size() - 1, -1, -1):
		if now - float(bubbles[i].born) >= BUBBLE_SECONDS:
			bubbles.remove_at(i)
	if bubbles.is_empty() or _modal_open():
		return plan
	var calm := Prefs.on("ui", "reduce_motion")
	var sb := _bubble_box()
	var inset := Vector4(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP), sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_BOTTOM))
	var tail := _bubble_tail()
	var font := Fonts.sans(500)
	var fs := maxi(BUBBLE_PX, Fonts.MIN_PX)
	for b in bubbles:
		var p = b.p
		if p.dead or p.away != null:
			continue
		var pp: Vector2 = main.view_pos(p)
		var head := _screen(pp.x, pp.y - BUBBLE_HEAD)
		if head.x < -40.0 or head.x > vp.x + 40.0 or head.y < -40.0 or head.y > vp.y + 40.0:
			continue
		var age := now - float(b.born)
		var words: Vector2 = font.get_multiline_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, BUBBLE_MAX_W, fs)
		var size := Vector2(maxf(words.x + inset.x + inset.z, 44.0), words.y + inset.y + inset.w)
		var lift := 0.0 if calm else BUBBLE_FLOAT * clampf(age / BUBBLE_SECONDS, 0.0, 1.0)
		var tip := head + Vector2(0.0, -BUBBLE_GAP - lift)
		# the tail is at the left of the picture: a speaker too near the right edge gets it turned round
		var left := tip.x - float(tail[0])
		var flip := false
		if left + size.x > vp.x - BUBBLE_MARGIN:
			var mirrored := tip.x + float(tail[0]) - size.x
			if mirrored >= BUBBLE_MARGIN:
				left = mirrored
				flip = true
		var x := clampf(left, BUBBLE_MARGIN, maxf(BUBBLE_MARGIN, vp.x - BUBBLE_MARGIN - size.x))
		var y := maxf(BUBBLE_MARGIN, tip.y - float(tail[1]) - size.y)
		var rect := Rect2(x, y, size.x, size.y)
		plan.append({
			"who": p.id, "text": b.text, "lines": maxi(1, roundi(words.y / font.get_height(fs))), "size": fs, "rect": rect,
			"tip": Vector2(rect.end.x - float(tail[0]) if flip else rect.position.x + float(tail[0]), rect.end.y + float(tail[1])),
			"flip": flip, "alpha": bubble_alpha(age, calm), "framed": _bubble_framed,
		})
	return plan


## Puts the bubbles on the screen (see bubble_plan): the frame, mirrored when its tail is at the right, and the
## words in the dark ink of paper.
func _draw_bubbles(vp: Vector2) -> void:
	drawn_bubbles = 0
	var plan := bubble_plan(vp)
	if plan.is_empty():
		return
	var sb := _bubble_box()
	var font := Fonts.sans(500)
	var tail := _bubble_tail()
	for b in plan:
		var rect: Rect2 = b.rect
		var a: float = b.alpha
		var flip: bool = b.flip
		if flip:
			draw_set_transform_matrix(Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(rect.position.x * 2.0 + rect.size.x, 0.0)))
		if sb is StyleBoxTexture:
			sb.modulate_color = Color(1, 1, 1, a)
			draw_style_box(sb, rect)
		else:
			(sb as StyleBoxFlat).bg_color = Color(Hud.PAPER, a)
			(sb as StyleBoxFlat).border_color = Color(Hud.PAPER_INK, 0.55 * a)
			draw_style_box(sb, rect)
			# the tail: a small triangle under the foot, with its two sides in the edge's colour
			var base := rect.end.y - 1.0
			var tri := PackedVector2Array([Vector2(rect.position.x + float(tail[0]) - 3.0, base), Vector2(rect.position.x + float(tail[0]) + 9.0, base), Vector2(rect.position.x + float(tail[0]), rect.end.y + float(tail[1]))])
			draw_colored_polygon(tri, Color(Hud.PAPER, a))
			draw_polyline(PackedVector2Array([tri[0], tri[2], tri[1]]), Color(Hud.PAPER_INK, 0.55 * a), 1.0, true)
		if flip:
			draw_set_transform_matrix(Transform2D.IDENTITY)
		var fs: int = b.size
		var inset := Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		draw_multiline_string(font, rect.position + inset + Vector2(0.0, font.get_ascent(fs)), b.text, HORIZONTAL_ALIGNMENT_LEFT, BUBBLE_MAX_W, fs, -1, Color(Hud.PAPER_INK, a))
		drawn_bubbles += 1


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim = main.sim
	var z: float = main.zoom_px
	var vp := get_viewport_rect().size
	var sel = main.selection

	drawn_sections = 0
	drawn_reach = 0
	drawn_spawns = 0
	drew_alarm = false
	if main.fields:
		_draw_fields(sim, z, vp)
	_draw_alarm(sim, z, vp)

	# wall damage bars across the damaged piece
	for s in sim.segments:
		if s.hp >= s.max_hp * 0.95:
			continue
		var p := _screen(s.obj.cx, s.obj.cy)
		if p.x < -60 or p.y < -60 or p.x > vp.x + 60 or p.y > vp.y + 60:
			continue
		var w := clampf((s.to - s.from) * z * 0.45, 28.0, 80.0)
		var f: float = s.hp / s.max_hp
		_pill(Rect2(p.x - w / 2 - 2, p.y - 3.5, w + 4, 7), PILL)
		var col := Color("#e0584a") if f < 0.34 else (Color("#e8953a") if f < 0.67 else Color("#9cc46a"))
		_pill(Rect2(p.x - w / 2, p.y - 1.5, maxf(3.0, w * f), 3), col)

	# selection
	if sel != null and (sel.kind == "person" or sel.kind == "zombie"):
		var e = sel.ref
		if not (sel.kind == "zombie" and e.state == "dead") and not (sel.kind == "person" and e.away != null):
			var ep: Vector2 = main.view_pos(e)
			var a := _screen(ep.x - 0.48, ep.y - 0.92)
			var b := _screen(ep.x + 0.48, ep.y + 0.42)
			var L := maxf(5.0, (b.x - a.x) * 0.22)
			var col := ACCENT if sel.kind == "person" else Color("#e2685a")
			for c in [[a.x, a.y, 1, 1], [b.x, a.y, -1, 1], [a.x, b.y, 1, -1], [b.x, b.y, -1, -1]]:
				draw_polyline(PackedVector2Array([Vector2(c[0] + c[2] * L, c[1]), Vector2(c[0], c[1]), Vector2(c[0], c[1] + c[3] * L)]), col, 2.0, true)
			if sel.kind == "person" and not e.downed:
				_dashed_circle(_screen(ep.x, ep.y), float(e.gun.range) * z, Color(ACCENT, 0.35), 1.2)
	elif sel != null and sel.kind == "segment":
		var box := section_rect(sel.ref)
		var a := _screen(box.position.x, box.position.y)
		var b := _screen(box.end.x, box.end.y)
		for edge in [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b], [b, Vector2(a.x, b.y)], [Vector2(a.x, b.y), a]]:
			_dashed_line(edge[0], edge[1], ACCENT, 2.0)
	var hover = main.hover
	if hover != null and (sel == null or hover != sel.ref):
		var hp: Vector2 = main.view_pos(hover)
		var a := _screen(hp.x - 0.45, hp.y - 0.88)
		draw_rect(Rect2(a, Vector2(0.9, 1.28) * z), Color(1, 1, 1, 0.35), false, 1.0)

	# move order marker
	var om = main.order_mark
	if om != null and main.clock - om.t < 0.7:
		var k: float = (main.clock - om.t) / 0.7
		draw_arc(_screen(om.x, om.y), (0.2 + k * 0.5) * z, 0, TAU, 32, Color(ACCENT, 1.0 - k), 2.0, true)

	# names under people
	if z >= 16.0:
		var font := Fonts.cond(600)
		var fs := maxi(NAME_PX, Fonts.MIN_PX)
		for p in sim.people:
			if p.away != null:
				continue # off the map on a trip: nothing to label
			var pp: Vector2 = main.view_pos(p)
			var pos := _screen(pp.x, pp.y + 0.52)
			if pos.x < -40 or pos.x > vp.x + 40 or pos.y < -20 or pos.y > vp.y + 20:
				continue
			var label: String = p.first
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
			var selected: bool = sel != null and sel.ref == p
			var bg := Color(ACCENT, 0.92) if selected else (Color(44 / 255.0, 40 / 255.0, 20 / 255.0, 0.86) if p.drafted else Color(12 / 255.0, 22 / 255.0, 19 / 255.0, 0.74))
			_pill(Rect2(pos.x - tw / 2, pos.y - 8, tw, 16), bg)
			var fg := Color("#1a1508") if selected else (ACCENT if p.drafted else INK)
			draw_string(font, Vector2(pos.x - tw / 2, pos.y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, tw, fs, fg)
			if p.hp < 100.0:
				draw_rect(Rect2(pos.x - 14, pos.y + 10, 28, 4), PILL)
				draw_rect(Rect2(pos.x - 13.5, pos.y + 10.5, 27.0 * p.hp / 100.0, 3), Color("#d0493a") if p.hp < 35 else Color("#8fb85a"))
			if p.reloading > 0.0:
				var k: float = 1.0 - p.reloading / float(p.gun.reload)
				var hy := _screen(pp.x, pp.y - 0.53 - 0.45).y
				draw_arc(Vector2(pos.x, hy), 6, 0, TAU, 24, Color(PILL, 0.7), 3.5, true)
				draw_arc(Vector2(pos.x, hy), 6, -PI / 2, -PI / 2 + k * TAU, 24, ACCENT, 2.0, true)

	# what people say, over everything else
	_draw_bubbles(vp)
