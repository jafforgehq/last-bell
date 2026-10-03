## In-world labels drawn at screen size: names under people, health and
## reload rings, wall damage bars, selection brackets, range circle and the
## move-order marker. And the night tools' drawings: the fields-of-fire view (key V:
## every wall section tinted by how many guns reach it, each gun's reach, and on the
## forecast night where the dead come in) and the marker of the alarm (the lure) on
## the wall section it rings at. And (round 4) what people say: speech bubbles over their heads. And
## (round 5) the marks of the Jobs screen while it is open (`main.jobs_hover`): a faint ring and the seats
## at every station, a firm ring and name at what the page points at, a ring at a night post, a box round a person.
## And (round 17, avatar mode only) the survivor the player plays: the crosshair at the pointer, the aim line from the
## gun, the ring of a reload and the YOU tag over their head (`_draw_avatar`). And (round 18) what E would do: the prompt
## beside the nearest thing in reach, the steady-stance mark on a post and the bench's ring (`_draw_interact`).
## All of it is a view: nothing here changes the rules.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const S := preload("res://scripts/render/shapes.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Frames := preload("res://scripts/ui/frames.gd")
const Prefs := preload("res://scripts/prefs.gd")
const TalkCard := preload("res://scripts/ui/talk_card.gd")
const TILE := 64.0
const ACCENT := Color(0.941, 0.761, 0.29)
## The size of the names under people: the same floor as the HUD's text (Fonts.MIN_PX).
const NAME_PX := 12
## The size of the YOU tag over the avatar's head.
const YOU_PX := 12
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
## The Jobs screen's marks (round 5; main.gd's `jobs_hover`, set by scripts/ui/jobs_screen.gd): while the page is up every
## station wears a faint ring in the HUD's gold with its seats under it; the one the page points at (a row's station, a
## station card, a station on a list) a firm one with its name and who is on it, and a night post the same in the
## blue of the night; a person a gold box. A place that is out of the window has an arrow at its edge instead.
const JOB_STATION := ACCENT
const JOB_POST := ALARM
const JOB_FAINT := 0.4
const JOB_LIT := 0.95
## How far in from the window's edge the arrows are kept, and the size of the seat marks.
const JOB_EDGE := 48.0
const JOB_SEAT := 4.5

var main
## What the last draw put on the screen (for the tests: a section, a gun's reach or an arrow
## that is out of the window is not drawn, and does not count).
var drawn_sections := 0
var drawn_reach := 0
var drawn_spawns := 0
var drew_alarm := false
## The Jobs screen's marks of the last draw: the stations drawn (and how many of them were lit), whether a night post
## was, how many arrows were drawn at the window's edge for a place that is out of it.
var drawn_job_stations := 0
var drawn_job_lit := 0
var drew_job_post := false
var drawn_job_edges := 0
## How many people wore the brackets and the ring of the selection at the last draw.
var drawn_selected := 0
## The avatar's marks (round 17, avatar mode only) at the last draw: the crosshair at the pointer (and where, in screen pixels),
## the aim line from the muzzle (and the tile where it stops, and whether it stops on one of the dead), the ring of a reload
## (and how far round it is, 0 to 1) and the YOU tag over the head.
var drew_crosshair := false
var drew_aim_line := false
var drew_reload_ring := false
var drew_you := false
## The crosshair is the greyed one (the trigger would only hit the face of a walkway: `Avatar.fire_blocked`) and its hint is drawn.
var crosshair_blocked := false
var drew_blocked_hint := false
var crosshair_at := Vector2.ZERO
var aim_end := Vector2.ZERO
var aim_on_target := false
var reload_progress := 0.0
## What people are saying: [{"p": Person, "text", "born": main.clock}], the oldest first; and how many bubbles
## the last draw put on the screen.
var bubbles: Array = []
var drawn_bubbles := 0
## What E would do (round 18), at the last draw: the prompt's words ("E  Talk to Dez"; with a refusal "E  Take the gate post: Dez is at
## the post"; "" when there is no prompt to show), whether its pill was drawn (it is not under a modal, a menu or a place, nor when
## every side of the thing is under a board of the HUD), whether the thing may be used (a dimmer prompt when not), the pill's
## rectangle, the thing the prompt is on ("kind:id") and the marks of a post held and of a bench session (and how far round it is).
var drew_prompt := false
var prompt_text := ""
var prompt_ok := true
var prompt_rect := Rect2()
var prompt_key := ""
var drew_brace := false
var drew_bench_ring := false
var bench_progress := 0.0
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
		var post: Vector2 = sim.tactics.post_pos(p)
		reach.append({"id": p.id, "at": post, "r": sim.reach_at(p.gun, post, true)})
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


# ----------------------------------------------------- the Jobs screen's marks --

## What the Jobs screen has marked ({"station", "post", "person"}: main.gd's `jobs_hover`), or {} while it is shut
## (or for a main that has no such thing).
func _jobs_marks() -> Dictionary:
	var m = main.get("jobs_hover") if main != null else null
	return m if m is Dictionary else {}


## The marks of the Jobs screen: every station faintly, with its seats; what the page points at firmly, with its name
## and who is on it. Nothing at all while the page is shut. A view only: nothing here changes the rules.
func _draw_jobs(sim, z: float, vp: Vector2) -> void:
	var marks := _jobs_marks()
	var jobs = sim.get("jobs")
	if marks.is_empty() or jobs == null:
		return
	var font := Fonts.cond(700)
	var calm := Prefs.on("ui", "reduce_motion")
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(float(main.clock) * 5.0)
	var view := Rect2(-24.0, -24.0, vp.x + 48.0, vp.y + 48.0)
	var lit_station := String(marks.get("station", ""))
	var r := clampf(z * 0.9, 16.0, 46.0)
	for st in jobs.stations():
		var id := String(st.id)
		var lit := id == lit_station
		var at: Vector2 = st.pos
		var c := _screen(at.x, at.y)
		var crew: Array = jobs.crew_of(id)
		var names: Array = []
		for p in crew:
			names.append(String(p.first))
		var who := ", ".join(names) if not names.is_empty() else "empty"
		if not view.has_point(c):
			if lit:
				_edge_mark(c, vp, JOB_STATION, "%s · %s" % [String(st.name), who], font)
			continue
		drawn_job_stations += 1
		var a := JOB_LIT if lit else JOB_FAINT
		if lit:
			drawn_job_lit += 1
			draw_circle(c, r, Color(JOB_STATION, 0.14))
			draw_arc(c, r, 0.0, TAU, 48, Color(JOB_STATION, a), 3.0, true)
			draw_arc(c, r + 3.0 + pulse * 5.0, 0.0, TAU, 48, Color(JOB_STATION, 0.55 * (1.0 - pulse * 0.6)), 2.0, true)
		else:
			draw_arc(c, r, 0.0, TAU, 48, Color(JOB_STATION, a), 2.0, true)
		_job_seats(c + Vector2(0.0, r + 12.0), int(st.seats), crew.size(), a)
		var label := "%s · %s" % [String(st.name), who] if lit else String(st.name)
		_tag(c + Vector2(0.0, -r - 13.0), label, font, Color(INK, 1.0 if lit else 0.85), Color(PILL, 0.9 if lit else 0.6), Color(JOB_STATION, a * 0.7) if lit else Color(0, 0, 0, 0))
	var post_id := String(marks.get("post", ""))
	var po: Dictionary = jobs.post(post_id) if post_id != "" else {}
	if not po.is_empty():
		var at: Vector2 = po.pos
		var c := _screen(at.x, at.y)
		var holder := "free"
		for p in sim.people:
			if not (p.dead or p.turned) and String(jobs.post_of(p).get("id", "")) == post_id:
				holder = String(p.first)
		var text := "Night post: %s · %s" % [String(po.name), holder]
		if view.has_point(c):
			drew_job_post = true
			var pr := clampf(z * 0.65, 12.0, 34.0)
			draw_circle(c, pr, Color(JOB_POST, 0.16))
			draw_arc(c, pr, 0.0, TAU, 40, Color(JOB_POST, JOB_LIT), 3.0, true)
			draw_arc(c, pr + 3.0 + pulse * 5.0, 0.0, TAU, 40, Color(JOB_POST, 0.55 * (1.0 - pulse * 0.6)), 2.0, true)
			_tag(c + Vector2(0.0, -pr - 13.0), text, font, INK, Color(PILL, 0.9), Color(JOB_POST, 0.7))
		else:
			_edge_mark(c, vp, JOB_POST, text, font)
	var person_id := String(marks.get("person", ""))
	if person_id != "":
		var who = _person(person_id)
		if who != null and who.away == null and not who.dead:
			var pp: Vector2 = main.view_pos(who)
			var corner := _screen(pp.x - 0.48, pp.y - 0.92)
			draw_rect(Rect2(corner, Vector2(0.96, 1.34) * z), Color(JOB_STATION, 0.9), false, 2.0)


## `seats` small marks in a row about `c`, the first `filled` of them solid.
func _job_seats(c: Vector2, seats: int, filled: int, alpha: float) -> void:
	var step := JOB_SEAT * 2.0 + 4.0
	var x0 := c.x - step * float(seats - 1) / 2.0
	for i in seats:
		var at := Vector2(x0 + step * float(i), c.y)
		draw_circle(at, JOB_SEAT + 1.5, Color(0.04, 0.07, 0.06, 0.7 * alpha))
		if i < filled:
			draw_circle(at, JOB_SEAT, Color(JOB_STATION, alpha))
		else:
			draw_arc(at, JOB_SEAT - 0.5, 0.0, TAU, 16, Color(JOB_STATION, alpha), 1.5, true)


## A place that is out of the window: an arrow at the window's edge on the way to it, with its words beside it.
func _edge_mark(target: Vector2, vp: Vector2, color: Color, text: String, font: Font) -> void:
	var mid := vp * 0.5
	var d := target - mid
	if d.length() < 1.0:
		return
	var half := mid - Vector2(JOB_EDGE, JOB_EDGE)
	var k := minf(minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001)), 1.0)
	var dir := d.normalized()
	var at := mid + d * k
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 14.0
	var pts := PackedVector2Array([tip, at - dir * 4.0 + side * 9.0, at - dir * 4.0 - side * 9.0])
	draw_colored_polygon(pts, Color(color, 0.95))
	draw_polyline(S.closed(pts), Color(0.1, 0.07, 0.04, 0.85), 1.5, true)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 10.0
	var label := at - Vector2(dir.x * (tw * 0.5 + 22.0), dir.y * 24.0)
	label.x = clampf(label.x, tw * 0.5 + 6.0, maxf(tw * 0.5 + 6.0, vp.x - tw * 0.5 - 6.0))
	label.y = clampf(label.y, 14.0, maxf(14.0, vp.y - 14.0))
	_tag(label, text, font, INK, Color(PILL, 0.92), Color(color, 0.7))
	drawn_job_edges += 1


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


## The rectangles of the HUD's boards that cover the world (the HUD says; a stand-in without the question has none).
func _covered_by_hud() -> Array:
	var hud = main.get("hud") if main != null else null
	return hud.covered_rects() if hud != null and hud.has_method("covered_rects") else []


func _under_hud(rect: Rect2, covered: Array) -> bool:
	for r in covered:
		if (r as Rect2).intersects(rect):
			return true
	return false


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
	var covered := _covered_by_hud()
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
		# (a bubble that would be under a board of the HUD is not drawn: the line is in the dock, in a toast and on the card as well)
		if _under_hud(rect, covered):
			continue
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


## A selected person's marks: the ellipse of a ring at their feet (the primary's heavier), the four corner brackets, and for
## one person alone the dashed circle of how far their gun reaches.
func _mark_person(e, primary: bool, alone: bool, z: float) -> void:
	drawn_selected += 1
	var ep: Vector2 = main.view_pos(e)
	var a := _screen(ep.x - 0.48, ep.y - 0.92)
	var b := _screen(ep.x + 0.48, ep.y + 0.42)
	var L := maxf(5.0, (b.x - a.x) * 0.22)
	draw_set_transform(_screen(ep.x, ep.y), 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, 0.42 * z, 0, TAU, 28, Color(ACCENT, 0.95 if primary else 0.8), 2.5 if primary else 1.8, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for c in [[a.x, a.y, 1, 1], [b.x, a.y, -1, 1], [a.x, b.y, 1, -1], [b.x, b.y, -1, -1]]:
		draw_polyline(PackedVector2Array([Vector2(c[0] + c[2] * L, c[1]), Vector2(c[0], c[1]), Vector2(c[0], c[1] + c[3] * L)]), ACCENT, 2.0, true)
	if alone and not e.downed:
		_dashed_circle(_screen(ep.x, ep.y), main.sim.reach_of(e.gun, e) * z, Color(ACCENT, 0.35), 1.2)


# ------------------------------------------------------- the avatar's marks --

## The crosshair's colours: a dark edge under a bright line (it must read on grass, on concrete and in the dark), red while the
## shot would land on one of the dead. Its ring is as wide as the gun's cone is at the pointer, never under CROSS_MIN pixels.
const CROSS_EDGE := Color(0.04, 0.07, 0.06, 0.9)
const CROSS_INK := Color(0.96, 0.94, 0.86, 0.95)
const CROSS_HIT := Color("#ff7d6e")
const CROSS_MIN := 10.0
## The crosshair while the shot would only hit the face of a walkway: grey, and what to do about it near it.
const CROSS_BLOCKED := Color(0.62, 0.65, 0.62, 0.8)
const BLOCKED_HINT := "Climb a ladder"
const CROSS_MAX := 46.0
## The aim line: how bright it is at the muzzle and at the end of the gun's reach, and the pieces it is drawn in.
const AIM_NEAR := 0.75
const AIM_FAR := 0.08
const AIM_PIECES := 14
## The reload ring round the avatar's body: its colour while it fills.
const RING_TRACK := Color(0.04, 0.07, 0.06, 0.5)


## What the avatar's hands and gun look like: the aim line from the muzzle to the first thing the shot would hit (it fades
## with the distance and is hidden while the gun is being reloaded or has no barrel), the ring of a reload round the body, the
## YOU tag over the head and the crosshair where the pointer is (not over a menu, a page or a HUD control). Not in the old yard.
func _draw_avatar(sim, z: float, vp: Vector2) -> void:
	if main.get("avatar_mode") != true:
		return
	var me = sim.avatar.player()
	if me == null or me.dead or me.turned or me.away != null:
		return
	var pp: Vector2 = main.view_pos(me)
	var hands_off: bool = main.has_method("avatar_hands_off") and main.avatar_hands_off()
	var gun: Dictionary = me.gun
	# (what is in the hand: a gun that the stores cannot feed is the butt of it, which has no line to draw)
	var live: Dictionary = sim.gun_of(me)
	var melee: bool = bool(live.get("melee", false))
	# the line from the gun
	if not hands_off and not me.downed and not melee and me.reloading <= 0.0:
		var shoulder: Vector2 = sim.avatar.shoulder(me)
		var muzzle: Vector2 = sim.muzzle(me, me.aim)
		var reach: float = sim.reach_of(live, me)
		var res: Dictionary = sim.avatar.trace(shoulder, me.aim, reach)
		var off := pp - Vector2(me.x, me.y)    # (the figure is drawn up to a step behind the rules')
		var end: Vector2 = res.end
		var a := _screen(muzzle.x + off.x, muzzle.y + off.y)
		var b := _screen(end.x + off.x, end.y + off.y)
		aim_end = end
		aim_on_target = res.z != null
		if a.distance_to(b) > 4.0:
			drew_aim_line = true
			var span := maxf(1.0, shoulder.distance_to(muzzle) + reach)
			var pieces := clampi(int(a.distance_to(b) / 28.0), 2, AIM_PIECES)
			var base := muzzle.distance_to(shoulder)
			for i in pieces:
				var t0 := float(i) / pieces
				var t1 := float(i + 1) / pieces
				var reach_share := clampf((base + muzzle.distance_to(end) * t0) / span, 0.0, 1.0)
				var col := Color(CROSS_HIT if aim_on_target else CROSS_INK, lerpf(AIM_NEAR, AIM_FAR, reach_share))
				draw_line(a.lerp(b, t0), a.lerp(b, t1), col, 1.5, true)
			if aim_on_target:
				draw_arc(b, 4.0, 0, TAU, 12, Color(CROSS_HIT, 0.85), 1.5, true)
	# the reload ring
	if me.reloading > 0.0 and not bool(gun.get("melee", false)):
		var total: float = maxf(0.01, float(gun.get("reload", 1.0)) * float(sim.traits.mult(me, "reload")))
		reload_progress = clampf(1.0 - me.reloading / total, 0.0, 1.0)
		drew_reload_ring = true
		var c := _screen(pp.x, pp.y - 0.45)
		var r := maxf(18.0, 0.66 * z)
		draw_arc(c, r, 0, TAU, 40, RING_TRACK, 4.0, true)
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + reload_progress * TAU, 40, ACCENT, 3.0, true)
	# the YOU tag over the head (not while they are speaking: the bubble has that place)
	var speaking := false
	for bubble in bubbles:
		if bubble.p == me:
			speaking = true
	if not speaking:
		var head := _screen(pp.x, pp.y - BUBBLE_HEAD)
		if head.x > -40.0 and head.x < vp.x + 40.0 and head.y > -20.0 and head.y < vp.y + 40.0:
			var font := Fonts.cond(700, 1)
			var fs := maxi(YOU_PX, Fonts.MIN_PX)
			var w := font.get_string_size("YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
			_pill(Rect2(head.x - w / 2.0, head.y - 22.0, w, 16.0), ACCENT)
			draw_string(font, Vector2(head.x - w / 2.0, head.y - 22.0 + fs * 0.9), "YOU", HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color("#1a1508"))
			drew_you = true
	# the crosshair (none for one who is down: there is nothing in their hands)
	if hands_off or me.downed or bool(main.get("over_hud")):
		return
	var at: Vector2 = main.mouse_screen
	if not Rect2(Vector2.ZERO, vp).has_point(at):
		return
	var radius := CROSS_MIN
	if not melee:
		var muzzle_px := _screen(me.x, me.y - 0.3)
		var cone: float = sim.avatar.spread_of(me, live)
		radius = clampf(muzzle_px.distance_to(at) * cone * 0.5, CROSS_MIN, CROSS_MAX)
	# a trigger pull that would only hit the face of a walkway does nothing (a dry click): the crosshair says so
	crosshair_blocked = not melee and sim.avatar.has_method("fire_blocked") and bool(sim.avatar.fire_blocked(me))
	var ink: Color = CROSS_BLOCKED if crosshair_blocked else (CROSS_HIT if aim_on_target else CROSS_INK)
	for pass_ in 2:
		var col: Color = CROSS_EDGE if pass_ == 0 else ink
		var w := 4.0 if pass_ == 0 else 2.0
		draw_arc(at, radius, 0, TAU, 32, col, w, true)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(at + dir * (radius - 3.0), at + dir * (radius + 6.0), col, w, true)
	draw_circle(at, 1.8, CROSS_EDGE)
	draw_circle(at, 1.2, ink)
	crosshair_at = at
	drew_crosshair = true
	if crosshair_blocked:
		var hint_font := Fonts.sans(600)
		var hw := hint_font.get_string_size(BLOCKED_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 12.0
		var hbox := Rect2(clampf(at.x - hw / 2.0, 4.0, maxf(4.0, vp.x - hw - 4.0)), minf(at.y + radius + 14.0, vp.y - 24.0), hw, 18.0)
		_pill(hbox, Color(0.04, 0.07, 0.06, 0.82))
		draw_string(hint_font, Vector2(hbox.position.x, hbox.position.y + FIELD_PX + 1.0), BLOCKED_HINT, HORIZONTAL_ALIGNMENT_CENTER, hw, FIELD_PX, Color(0.9, 0.9, 0.84, 0.95))
		drew_blocked_hint = true


# --------------------------------------------------------- what E would do --

## How much nearer another thing has to be before the prompt leaves the one it is on (tiles): it does not flicker between two.
const PROMPT_HOLD := 0.3
## The pill's slate, the size of its key and its limit in width, and how far it keeps from the thing it is for.
const PROMPT_BACK := Color(0.043, 0.078, 0.067, 0.93)
const PROMPT_KEY := 20.0
const PROMPT_MAX_W := 340.0
const PROMPT_GAP := 10.0
## What E does to a person who has the card open (the words of the prompt then).
const PROMPT_END_TALK := "End the talk with %s"


## The thing the prompt rests on: the nearest candidate, or the one it was on (`held`, a "kind:id") while that is still in reach and
## not more than PROMPT_HOLD tiles farther than the nearest.
static func choose_prompt(cands: Array, held: String) -> Dictionary:
	if cands.is_empty():
		return {}
	var nearest: Dictionary = cands[0]
	if held != "" and held != key_of(nearest):
		for c in cands:
			if key_of(c) == held:
				if float(c.get("dist", 0.0)) <= float(nearest.get("dist", 0.0)) + PROMPT_HOLD:
					return c
				break
	return nearest


## Moves what the avatar has begun (a bench being worked, a post held: their "kind:id" in `began`) to the front of `cands` when it is within
## PROMPT_HOLD tiles of the nearest one: E is to end it, and a person standing as near would otherwise be what E does (the rules rank a
## person first within a third of a tile).
static func started_first(cands: Array, began: Array) -> Array:
	if cands.size() < 2 or began.is_empty() or began.has(key_of(cands[0])):
		return cands
	var limit := float(cands[0].get("dist", 0.0)) + PROMPT_HOLD
	for i in range(1, cands.size()):
		if began.has(key_of(cands[i])) and float(cands[i].get("dist", 0.0)) <= limit:
			var out: Array = cands.duplicate()
			var c = out.pop_at(i)
			out.push_front(c)
			return out
	return cands


## "kind:id" of a candidate ("" for none).
static func key_of(c: Dictionary) -> String:
	return "" if c.is_empty() else "%s:%s" % [String(c.get("kind", "")), String(c.get("id", ""))]


## `name` of the interact module, or `fallback` (a stand-in may have no such thing).
func _prop(it, prop_name: String, fallback):
	var v = it.get(prop_name) if it != null else null
	return fallback if v == null else v


## Whether a prompt may be shown at all: an avatar in the yard, with no menu, page or place over it and the run not over.
func _prompt_allowed() -> bool:
	if main == null or main.sim == null or main.get("avatar_mode") != true:
		return false
	if main.has_method("avatar_hands_off") and main.avatar_hands_off():
		return false
	if main.has_method("raid_open") and main.raid_open():
		return false
	return not _modal_open()


## The thing E would use now (the nearest candidate of the rules' `interact.candidates()`, held by PROMPT_HOLD), or {} when there is
## none or the prompt is not to be shown. main.gd's E key uses what this says, so that E does what the pill says.
func prompt_candidate() -> Dictionary:
	var it = TalkCard.interact_of(main.sim if main != null else null)
	if it == null or not _prompt_allowed():
		prompt_key = ""
		return {}
	var began: Array = []
	if String(_prop(it, "working", "")) == "bench":
		began.append("bench:bench")
	if String(_prop(it, "posted", "")) != "":
		began.append("post:%s" % String(_prop(it, "posted", "")))
	var pick := choose_prompt(started_first(it.candidates(), began), prompt_key)
	prompt_key = key_of(pick)
	return pick


## The words of a candidate's prompt: {"label", "why", "ok", "text" ("E  Talk to Dez", "E  Take the gate post: Dez is at the post")}.
## What E does to a person whose card is open is not what the rules' label says (it would talk again: E closes the card), so the words say
## that; the rules' own labels already offer to leave a post held and to stop a bench worked.
func prompt_for(c: Dictionary, it) -> Dictionary:
	var label := String(c.get("label", ""))
	var kind := String(c.get("kind", ""))
	var id := String(c.get("id", ""))
	var ok := bool(c.get("ok", true))
	var why := String(c.get("why", ""))
	var hud = main.get("hud") if main != null else null
	if kind == "person" and hud != null and hud.has_method("talk_person"):
		var open_for = hud.talk_person()
		if open_for != null and String(open_for.id) == id:
			label = PROMPT_END_TALK % String(open_for.first)
			ok = true
	if ok:
		why = ""
	return {"label": label, "why": why, "ok": ok, "text": "E  %s" % label if why == "" else "E  %s: %s" % [label, why]}


## Where the thing a candidate is on is on the screen (pixels): a person at their feet as drawn, anything else where the rules say.
func _spot_of(c: Dictionary) -> Vector2:
	if String(c.get("kind", "")) == "person":
		var who = _person(String(c.get("id", "")))
		if who != null:
			var pp: Vector2 = main.view_pos(who)
			return _screen(pp.x, pp.y)
	var at: Vector2 = c.get("pos", Vector2.ZERO)
	return _screen(at.x, at.y)


## The marks of what the avatar is doing with their hands on the yard (not the gun's: `_draw_avatar` has those): the steady stance on a
## post, the bench's ring while they work it, and the prompt of what E would do beside the nearest thing in reach.
func _draw_interact(sim, z: float, vp: Vector2) -> void:
	var it = TalkCard.interact_of(sim)
	if it == null or main.get("avatar_mode") != true:
		return
	var me = sim.avatar.player()
	if me == null or me.dead or me.turned or me.away != null:
		return
	var pp: Vector2 = main.view_pos(me)
	var calm := Prefs.on("ui", "reduce_motion")
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(float(main.clock) * 4.0)
	# the steady stance: a green ring at the feet and the word beside them
	if String(_prop(it, "posted", "")) != "":
		var feet := _screen(pp.x, pp.y)
		draw_set_transform(feet, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, maxf(14.0, 0.55 * z), 0.0, TAU, 40, Color(PILL, 0.7), 4.5, true)
		draw_arc(Vector2.ZERO, maxf(14.0, 0.55 * z), 0.0, TAU, 40, Hud.OK, 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var font := Fonts.cond(700)
		# (on the left of the feet: the prompt's pill is on the right of them)
		_tag(feet + Vector2(-maxf(14.0, 0.55 * z) - 34.0, -0.1 * z), "Steady", font, Hud.OK, PROMPT_BACK, Color(Hud.OK, 0.7))
		drew_brace = true
	# the bench: a ring round the body that fills while they work
	if String(_prop(it, "working", "")) == "bench":
		var total := float(TalkCard.rule(it, "BENCH_SECONDS", 12.0))
		var left := float(_prop(it, "work_left", 0.0))
		bench_progress = clampf(1.0 - left / maxf(total, 0.01), 0.0, 1.0)
		var body := _screen(pp.x, pp.y - 0.45)
		var r := maxf(18.0, 0.55 * z)    # (round the body, under the YOU tag over the head; the reload ring has no room to be there too)
		draw_arc(body, r, 0.0, TAU, 48, RING_TRACK, 5.0, true)
		draw_arc(body, r, -PI / 2.0, -PI / 2.0 + bench_progress * TAU, 48, ACCENT, 3.5, true)
		_tag(body + Vector2(-r - 40.0, -4.0), "Bench %ds" % ceili(left), Fonts.cond(700), ACCENT, PROMPT_BACK, Color(ACCENT, 0.6))
		drew_bench_ring = true
	# the prompt
	var c := prompt_candidate()
	if c.is_empty():
		return
	var words := prompt_for(c, it)
	prompt_text = String(words.text)
	prompt_ok = bool(words.ok)
	var spot := _spot_of(c)
	var kind := String(c.kind)
	var rx := clampf(z * (1.1 if kind == "vehicle" else (0.7 if kind == "bench" else 0.5)), 14.0, 70.0)
	var ring: Color = ACCENT if prompt_ok else Hud.INK3
	# (the post that is held has its own green ring: the steady stance)
	if not (kind == "post" and String(_prop(it, "posted", "")) == String(c.id)):
		draw_set_transform(spot, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 40, Color(PILL, 0.65), 4.5, true)
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 40, Color(ring, (0.6 + 0.4 * pulse) if prompt_ok else 0.6), 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_prompt_pill(words, spot, rx, vp)


## The pill of the prompt: a gold key with E, the label, and for a refusal the reason in amber under it; beside the ring on the right,
## else on the left, else above, else below, whichever is in the window and not under a board of the HUD. Not drawn when none is.
func _draw_prompt_pill(words: Dictionary, spot: Vector2, rx: float, vp: Vector2) -> void:
	var font := Fonts.sans(600)
	var fs := maxi(FIELD_PX, Fonts.MIN_PX)
	var label := String(words.label)
	var why := String(words.why)
	var inner := PROMPT_MAX_W - PROMPT_KEY - 24.0
	var label_w := minf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, inner)
	var why_w := minf(font.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, inner, fs).x, inner) if why != "" else 0.0
	var lines := 2 if why != "" else 1
	var h := 24.0 if lines == 1 else 42.0
	var w := 8.0 + PROMPT_KEY + 8.0 + maxf(label_w, why_w) + 10.0
	var sides := [
		Vector2(spot.x + rx + PROMPT_GAP, spot.y - 0.4 * h - 6.0),
		Vector2(spot.x - rx - PROMPT_GAP - w, spot.y - 0.4 * h - 6.0),
		Vector2(spot.x - w / 2.0, spot.y - rx * 0.5 - PROMPT_GAP - h - 24.0),
		Vector2(spot.x - w / 2.0, spot.y + rx * 0.5 + PROMPT_GAP + 14.0),
	]
	var view := Rect2(4.0, 4.0, vp.x - 8.0, vp.y - 8.0)
	var covered := _covered_by_hud()
	var rect := Rect2()
	var found := false
	for at in sides:
		var r := Rect2(at, Vector2(w, h))
		if view.encloses(r) and not _under_hud(r, covered):
			rect = r
			found = true
			break
	if not found:
		return
	var ok: bool = prompt_ok
	var round_r := minf(12.0, rect.size.y * 0.5)
	draw_colored_polygon(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, round_r, 5), PROMPT_BACK)
	draw_polyline(S.closed(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, round_r, 5)), Color(ACCENT if ok else Hud.INK3, 0.8), 1.5, true)
	var key := Rect2(rect.position.x + 6.0, rect.position.y + 3.0, PROMPT_KEY, 18.0)
	draw_colored_polygon(S.rrect(key.position.x, key.position.y, key.size.x, key.size.y, 4.0, 4), ACCENT if ok else Hud.INK3)
	var kfont := Fonts.cond(700, 1)
	draw_string(kfont, Vector2(key.position.x, key.position.y + 14.0), "E", HORIZONTAL_ALIGNMENT_CENTER, key.size.x, fs, Color("#1a1508"))
	var tx := key.end.x + 8.0
	draw_string(font, Vector2(tx, rect.position.y + 3.0 + fs), label, HORIZONTAL_ALIGNMENT_LEFT, inner, fs, Hud.INK if ok else Hud.INK2)
	if why != "":
		draw_string(font, Vector2(tx, rect.position.y + 21.0 + fs), why, HORIZONTAL_ALIGNMENT_LEFT, inner, fs, Hud.WARN)
	prompt_rect = rect
	drew_prompt = true


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
	drawn_job_stations = 0
	drawn_job_lit = 0
	drew_job_post = false
	drawn_job_edges = 0
	drawn_selected = 0
	drew_crosshair = false
	crosshair_blocked = false
	drew_blocked_hint = false
	drew_aim_line = false
	drew_reload_ring = false
	drew_you = false
	drew_prompt = false
	prompt_text = ""
	prompt_rect = Rect2()
	drew_brace = false
	drew_bench_ring = false
	aim_on_target = false
	if main.fields:
		_draw_fields(sim, z, vp)
	_draw_alarm(sim, z, vp)
	_draw_jobs(sim, z, vp)

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

	# selection: a person wears the corner brackets, a ring at their feet and the circle of how far their gun reaches
	if sel != null and sel.kind == "person":
		if sel.ref.away == null:
			_mark_person(sel.ref, true, true, z)
	elif sel != null and sel.kind == "zombie":
		var e = sel.ref
		if e.state != "dead":
			var ep: Vector2 = main.view_pos(e)
			var a := _screen(ep.x - 0.48, ep.y - 0.92)
			var b := _screen(ep.x + 0.48, ep.y + 0.42)
			var L := maxf(5.0, (b.x - a.x) * 0.22)
			for c in [[a.x, a.y, 1, 1], [b.x, a.y, -1, 1], [a.x, b.y, 1, -1], [b.x, b.y, -1, -1]]:
				draw_polyline(PackedVector2Array([Vector2(c[0] + c[2] * L, c[1]), Vector2(c[0], c[1]), Vector2(c[0], c[1] + c[3] * L)]), Color("#e2685a"), 2.0, true)
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

	# the avatar's marks: the aim line, the reload ring, the YOU tag and the crosshair
	_draw_avatar(sim, z, vp)
	# what E would do: the prompt, the steady stance, the bench's ring
	_draw_interact(sim, z, vp)

	# what people say, over everything else
	_draw_bubbles(vp)
