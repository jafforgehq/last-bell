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
## beside the nearest thing in reach, the steady-stance mark on a post and the bench's ring (`_draw_interact`). And (round 19, avatar
## mode) the marks of the nights: from the forecast to dawn the walls the dead will come to wear a hatched bracket and "brunt, about
## 21:00" (`_draw_targets`), the avatar a faint ring as wide as the rally radius, brighter while someone is rallied, and the rallied a
## small chevron (`_draw_rally`), a plated brute a steel tell and a ring at its weak point that lights when the aim is near
## (`_draw_plated`), a breach that is hot a pulsing ring that says nobody will mend it under fire (`_draw_hot_breaches`), and the
## ring of the avatar's hands mending a wall (`_draw_mend`). And (round 25, avatar mode) the base's trouble: the markers of the open problems with their
## words and their time, the quarantine's sign, the labels of the stations that wait on something and the ring of the hands at a fix (`_draw_base`,
## scripts/render/base_marks.gd).
## All of it is a view: nothing here changes the rules.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const S := preload("res://scripts/render/shapes.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Frames := preload("res://scripts/ui/frames.gd")
const Prefs := preload("res://scripts/prefs.gd")
const TalkCard := preload("res://scripts/ui/talk_card.gd")
const WorldClick := preload("res://scripts/ui/world_click.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const StanceMarks := preload("res://scripts/render/stance_marks.gd")
const GateKit := preload("res://scripts/ui/gate_kit.gd")
const BaseMarks := preload("res://scripts/render/base_marks.gd")
const PromptKit := preload("res://scripts/render/prompt_kit.gd")
const HudStage := preload("res://scripts/ui/hud_stage.gd")
const TILE := 64.0
const ACCENT := Color(0.941, 0.761, 0.29)
## The size of the names under people: the same floor as the HUD's text (Fonts.MIN_PX).
const NAME_PX := 12
## HUD8: the minimal HUD names the crew within this many tiles of the avatar.
const NAME_NEAR_TILES := 6.0
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
## The marks of the nights (round 19). The brunt's colour is the spawn arrow's red (its text the arrow's); the rally ring is the HUD's
## green; a plated brute's steel is cold grey with a dark edge so that it reads on grass, concrete and in the dark; the weak point is
## amber, hot red-orange.
const BRUNT := SPAWN
const BRUNT_TEXT := SPAWN_TEXT
const BRUNT_FILL := 0.13
const BRUNT_FILL_CALM := 0.07
const RALLY := Color("#8fb85a")
const STEEL := Color("#aeb9c3")
const STEEL_DARK := Color("#4a5660")
const STEEL_EDGE := Color(0.04, 0.06, 0.07, 0.92)
const WEAK := Color("#ffb347")
const WEAK_HOT := Color("#ff7d6e")
const HOT := Color("#ff7d6e")
## How often the forecast is asked for the marks (seconds of the screen's clock), how near the aim has to pass a weak point for the ring to
## light (in weak-point radii), and the smallest the ring is drawn (pixels).
const NIGHT_REFRESH := 0.25
const WEAK_NEAR := 3.0
const WEAK_MIN_PX := 7.0
## How long the hatching's lines are apart, the brackets' arm and the dead's weak point height as the rules have it.
const HATCH_GAP := 12.0
## The gate's marks (round 22, avatar mode): the gateway and the lever are outlined faintly while the avatar is within GATE_NEAR tiles of the
## lever, or the gate is held open as the day ends (gold, with its words); and the gateway's ring pulses red while the gate is open in the dark
## (a breach that is not a wall: nobody mends it, a hand on the lever shuts it).
const GATE_NEAR := 7.0
## How long before the bell a gate held open is outlined in gold with its words (hours).
const GATE_REMIND_H := 1.0
const GATE_OUTLINE := Color("#9fc2d6")
const GATE_FAINT := 0.42

var main
## The nights' marks of the last draw (round 19; see the header): the brunt's brackets (how many were in the window, whether any, the tags
## [{"id", "text", "at"}] and whether the night is one that needs the player), the rally ring (its radius in pixels, whether someone is
## rallied, how many chevrons), the plated brutes drawn (and their weak-point rings [{"id", "at", "r", "near", "on"}]), the hot breaches
## (and their tags) and the ring of the hands at a wall (`mend_progress`, 0 to 1).
var drew_target_marks := false
var drawn_target_marks := 0
var target_tags: Array = []
var target_lit := false
var drew_rally_ring := false
var rally_ring_px := 0.0
var rally_lit := false
var drawn_rallied := 0
var drew_weak_marks := false
var drawn_weak_marks := 0
var drawn_plated := 0
var weak_marks: Array = []
var drew_hot_breach := false
var drawn_hot_breach := 0
var hot_tags: Array = []
var drew_mend_ring := false
var mend_progress := 0.0
## The gate's marks of the last draw (round 22): the faint outline of the gateway and the lever's ring (`drew_gate_outline`), the pulsing ring of
## an open gate in the dark (`drew_gate_pulse`), the words beside it (`gate_tag`: "held open", "gate open") and the gateway's box on the screen.
var drew_gate_outline := false
var drew_gate_pulse := false
var drew_gate_spot := false
var gate_tag := ""
var gate_box := Rect2()
var drew_gate_tag := false
var gate_tag_rect := Rect2()
## The floating word over the lever (round 23: "GATE (E)", from LABEL_R tiles, avatar mode): drawn at the last draw, and where it is on the screen.
var drew_gate_label := false
var gate_label_rect := Rect2()
## The gate's words waiting for their place (they are put down after the prompt, which they keep clear of): {"text", "color", "back", "ring"} or {}.
var _gate_words := {}
## What the forecast said at the last look (it is asked a few times a second, not every frame) and when.
var _night_f := {}
var _night_t := -1.0e9
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
## The flag of an order was drawn at the last draw (round 23).
var drew_flag := false
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
## WORLD: how far round the ring of the pill's key was at the last draw (0 to 1; -1 when the pill had none), and whether the greyed "Searched" stand-in was drawn.
var prompt_ring := -1.0
var drew_searched := false
var drew_brace := false
var drew_bench_ring := false
var bench_progress := 0.0
## Round 22, "Right button aims": the free pointer is over a thing the rules can use and the ring and pill were drawn for it (`drew_hover_ring`,
## the thing's "kind:id" in `hover_key`), or it is over one that is out of reach and its "Too far" tag was drawn (`drew_far_tag`).
var drew_hover_ring := false
var hover_key := ""
var drew_far_tag := false
## The base's trouble (round 25, scripts/render/base_marks.gd; avatar mode, the yard): the markers of the open problems and the quarantine's sign
## (`drew_problem_marks`, how many in `drawn_problem_marks`, how many with their words in `drawn_problem_labels`), the labels of the stations that
## wait on something (`drew_facility_labels`, `drawn_facility_labels`) and the ring of the avatar's own hands at a problem (`drew_fix_ring`, how far
## round it is in `fix_progress`, 0 to 1). `base_marks.record` (a test sets it) keeps what was drawn in `base_marks.tags`.
var base_marks := BaseMarks.new()
var drew_problem_marks := false
var drawn_problem_marks := 0
var drawn_problem_labels := 0
var drew_facility_labels := false
var drawn_facility_labels := 0
var drew_fix_ring := false
var fix_progress := 0.0
var _base_opts := {}
var _screen_cb := Callable()
var _bubble_sb: StyleBox = null
var _bubble_framed := false


func _screen(x: float, y: float) -> Vector2:
	return get_viewport().get_canvas_transform() * (Vector2(x, y) * TILE)


## `_screen` for a point (the callable the base's marks are given, so that they need no knowledge of the camera).
func _screen_at(at: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * (at * TILE)


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


## Forgets what the forecast said at the last look, so that the next draw asks again (a test that changed the night asks for it).
func forget_night() -> void:
	_night_t = -1.0e9


## The lookout's forecast as the marks use it (avatar mode only; {"given": false} otherwise), kept for NIGHT_REFRESH seconds.
func _night_forecast(sim) -> Dictionary:
	var now: float = main.clock
	if now >= _night_t and now - _night_t < NIGHT_REFRESH:
		return _night_f
	_night_t = now
	_night_f = sim.tactics.forecast() if String(sim.player_id) != "" else {"given": false}
	return _night_f


## Avatar mode (the nights' marks are only for it).
func _avatar_on(sim) -> bool:
	return main.get("avatar_mode") == true and String(sim.player_id) != ""


## What the fields-of-fire view shows, in tiles: {"sections": [{"id", "rect", "n" (guns
## that reach it), "color", "damaged"}], "reach": [{"id", "at", "r"}] (each gun at
## its post), "spawns": [{"at", "dir"}] (where the dead come in tonight, if the lookout
## has said), "brunt": the words under each arrow ("first about 21:00", avatar mode, when the lookout gave an hour)}. The rules' own numbers
## (sim.tactics), read and not changed.
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
	var brunt := NightKit.arrow_tag(f) if String(sim.player_id) != "" else ""
	return {"sections": sections, "reach": reach, "spawns": spawns, "brunt": brunt}


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
		_draw_spawn(sp, z, font, vp, String(plan.get("brunt", "")))


## A pulsing red arrow at a spawn point on the map's edge, pointing inward, with "from here".
func _draw_spawn(sp: Dictionary, z: float, font: Font, vp: Vector2, when: String = "") -> void:
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
	if when != "":
		_tag(out + Vector2(0.0, 20.0), when, font, SPAWN_TEXT)


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


# --------------------------------------------------------------- the nights' marks --

## Diagonal lines (a hatching) filling `box`, `gap` pixels apart, clipped to it.
func _hatch(box: Rect2, color: Color, gap: float, width: float = 1.5) -> void:
	var k := box.position.x - box.end.y + gap * 0.5
	var k_end := box.end.x - box.position.y
	while k < k_end:
		# the line y = x - k, between the box's left and right edges and its top and bottom
		var lo := maxf(box.position.x, box.position.y + k)
		var hi := minf(box.end.x, box.end.y + k)
		if hi - lo > 1.0:
			draw_line(Vector2(lo, lo - k), Vector2(hi, hi - k), color, width, true)
		k += gap


## The four corners of `box` as brackets: a dark stroke under a bright one, so that they read on any ground.
func _brackets(box: Rect2, color: Color, arm: float, width: float) -> void:
	for pass_ in 2:
		var col: Color = Color(0.05, 0.03, 0.03, 0.8) if pass_ == 0 else color
		var w := width + 2.0 if pass_ == 0 else width
		for c in [[box.position, 1.0, 1.0], [Vector2(box.end.x, box.position.y), -1.0, 1.0], [Vector2(box.position.x, box.end.y), 1.0, -1.0], [box.end, -1.0, -1.0]]:
			var at: Vector2 = c[0]
			draw_polyline(PackedVector2Array([at + Vector2(c[1] * arm, 0.0), at, at + Vector2(0.0, c[2] * arm)]), col, w, true)


## The walls the dead will come to, from the forecast to dawn (avatar mode): the sections the forecast names wear a hatched bracket in the
## spawn arrow's red, the first of them the words "brunt, about 21:00" (the others "brunt"). Quieter for an ordinary night, which needs
## nobody; a Big Night's is lit.
func _draw_targets(sim, z: float, vp: Vector2) -> void:
	if not _avatar_on(sim) or String(sim.phase) == "dawn":
		return
	var f := _night_forecast(sim)
	if not NightKit.has_outlook(f):
		return
	var ids: Array = f.get("sections", [])
	if ids.is_empty():
		return
	var lit := NightKit.needs_you(f)
	target_lit = lit
	var calm := Prefs.on("ui", "reduce_motion")
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(float(main.clock) * 3.0)
	var font := Fonts.cond(700)
	var view := Rect2(-30.0, -30.0, vp.x + 60.0, vp.y + 60.0)
	var first := true
	for id in ids:
		var seg = null
		for s in sim.segments:
			if int(s.id) == int(id):
				seg = s
				break
		if seg == null:
			continue
		var rect := section_rect(seg)
		var a := _screen(rect.position.x, rect.position.y)
		var b := _screen(rect.end.x, rect.end.y)
		var box := Rect2(a, b - a).grow(3.0)
		if not box.intersects(view):
			continue
		drew_target_marks = true
		drawn_target_marks += 1
		var strength := 1.0 if lit else 0.55
		draw_rect(box, Color(BRUNT, (BRUNT_FILL if lit else BRUNT_FILL_CALM) * (0.8 + 0.4 * pulse)))
		_hatch(box, Color(BRUNT, 0.34 * strength), HATCH_GAP)
		_brackets(box, Color(BRUNT, (0.7 + 0.3 * pulse) * strength + 0.1), clampf(minf(box.size.x, box.size.y) * 0.35, 9.0, 22.0), 3.0 if lit else 2.0)
		var text := NightKit.brunt_tag(f) if first else "brunt"
		first = false
		# (the tag is on the inner side of the wall, where the dead do not stand: they would hide it)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 10.0
		var c := box.get_center()
		var at := c
		match String(seg.side):
			"N":
				at = Vector2(c.x, box.end.y + 14.0)
			"S":
				at = Vector2(c.x, box.position.y - 14.0)
			"W":
				at = Vector2(box.end.x + tw / 2.0 + 6.0, c.y)
			"E":
				at = Vector2(box.position.x - tw / 2.0 - 6.0, c.y)
			_:
				at = Vector2(c.x, box.position.y - 14.0)
		at = Vector2(clampf(at.x, tw / 2.0 + 6.0, maxf(tw / 2.0 + 6.0, vp.x - tw / 2.0 - 6.0)), clampf(at.y, 14.0, maxf(14.0, vp.y - 14.0)))
		_tag(at, text, font, INK, Color(BRUNT.darkened(0.6), 0.92), Color(BRUNT, 0.95 if lit else 0.6))
		target_tags.append({"id": int(seg.id), "text": text, "at": at})


## The avatar's rally ring (avatar mode, where the nights' rules apply): a faint ring as wide as the radius within which the others shoot
## better for him; brighter while someone stands in it, and each of them wears a small chevron over the head.
func _draw_rally(sim, z: float, vp: Vector2) -> void:
	if not _avatar_on(sim):
		return
	var nights = sim.get("nights")
	if nights == null or not bool(nights.active()):
		return
	var me = sim.avatar.player()
	if me == null or me.dead or me.turned or me.downed or me.away != null:
		return
	var pp: Vector2 = main.view_pos(me)
	var c := _screen(pp.x, pp.y)
	var r: float = NightData.num("rally.radius", 9.0) * z
	var count := 0
	for p in sim.people:
		if p == me or p.dead or p.turned or p.away != null or not bool(nights.rallied(p)):
			continue
		count += 1
		var q: Vector2 = main.view_pos(p)
		var head := _screen(q.x, q.y - BUBBLE_HEAD - 0.25)
		if head.x < -20.0 or head.x > vp.x + 20.0 or head.y < -20.0 or head.y > vp.y + 20.0:
			continue
		drawn_rallied += 1
		var pts := PackedVector2Array([head + Vector2(-6.0, 3.0), head + Vector2(0.0, -3.0), head + Vector2(6.0, 3.0)])
		draw_polyline(pts, Color(0.04, 0.07, 0.06, 0.85), 4.5, true)
		draw_polyline(pts, RALLY, 2.5, true)
	drew_rally_ring = true
	rally_ring_px = r
	rally_lit = count > 0
	var a := 0.42 if rally_lit else 0.17
	if HudStage.minimal_on(main):
		# (HUD8: the ring is twelve short strokes of its circle: the radius is said, and the middle of the window, where the fight is, is not crossed by a line)
		var n := 12
		for k in n:
			var from := TAU * float(k) / float(n)
			draw_arc(c, r, from, from + TAU / float(n) * 0.14, 5, Color(RALLY, a * 1.4), 2.5 if rally_lit else 2.0, true)
	else:
		draw_arc(c, r, 0.0, TAU, clampi(int(r / 5.0), 48, 160), Color(RALLY, a), 2.0 if rally_lit else 1.5, true)
	if rally_lit:
		draw_circle(c, r, Color(RALLY, 0.04))


## A plated brute's steel: shoulder plates and a chest plate over the body, drawn on the figure as the pawn is (its box, from the feet).
func _draw_plates(e, zp: Vector2, z: float) -> void:
	var box: Rect2 = Art.hit_box(Art.kind_of(e), Art.size_of(e))
	var hw := box.size.x * 0.5
	var top := box.position.y
	var h := box.size.y
	var y0 := top + h * 0.38
	var y1 := top + h * 0.68
	var xw := hw * 0.6
	var chest := PackedVector2Array([
		_screen(zp.x - xw, zp.y + y0), _screen(zp.x + xw, zp.y + y0), _screen(zp.x + xw * 0.82, zp.y + y1), _screen(zp.x - xw * 0.82, zp.y + y1),
	])
	for side in [-1.0, 1.0]:
		var at := _screen(zp.x + side * xw, zp.y + y0 + h * 0.03)
		var pr := maxf(4.0, hw * 0.27 * z)
		draw_circle(at, pr + 1.5, STEEL_EDGE)
		draw_circle(at, pr, STEEL_DARK)
		draw_arc(at, pr * 0.62, PI * 1.1, PI * 1.9, 8, STEEL, 2.0, true)
	draw_colored_polygon(chest, Color(STEEL, 0.78))
	draw_polyline(S.closed(chest), STEEL_EDGE, 2.0, true)
	# the lit top edge, a plate seam and the rivets
	draw_line(chest[0].lerp(chest[3], 0.08), chest[1].lerp(chest[2], 0.08), Color(1, 1, 1, 0.55), 1.5, true)
	var mid_l := chest[0].lerp(chest[3], 0.52)
	var mid_r := chest[1].lerp(chest[2], 0.52)
	draw_line(mid_l, mid_r, Color(STEEL_DARK, 0.9), 1.5, true)
	for k in [0.18, 0.5, 0.82]:
		draw_circle(chest[0].lerp(chest[1], k).lerp(chest[3].lerp(chest[2], k), 0.78), 1.6, STEEL_DARK)


## The flag an order by radio put on the ground (round 23, main.gd `order_flag`: "Hold here" at a spot, "To the walls" at a post): a ring, a pole and a
## pennant at the spot for `main.FLAG_S` seconds, fading in the last second. `drew_flag` says it was drawn (a test reads it).
func _draw_order_flag(z: float) -> void:
	drew_flag = false
	var fl = main.get("order_flag")
	if fl == null:
		return
	var age: float = float(main.clock) - float(fl.t)
	var life: float = float(main.FLAG_S)
	if age < 0.0 or age > life:
		return
	var a := clampf(life - age, 0.0, 1.0)
	var foot := _screen(float(fl.x), float(fl.y))
	var top := foot + Vector2(0.0, -0.95 * z)
	draw_arc(foot, 0.3 * z, 0.0, TAU, 28, Color(0.04, 0.03, 0.02, 0.7 * a), 4.0, true)
	draw_arc(foot, 0.3 * z, 0.0, TAU, 28, Color(ACCENT, 0.9 * a), 2.0, true)
	draw_line(foot, top, Color(0.04, 0.03, 0.02, 0.85 * a), 4.0, true)
	draw_line(foot, top, Color(INK, a), 2.0, true)
	var sail := PackedVector2Array([top, top + Vector2(0.55 * z, 0.17 * z), top + Vector2(0.0, 0.36 * z)])
	draw_colored_polygon(sail, Color(ACCENT, a))
	draw_polyline(PackedVector2Array([sail[0], sail[1], sail[2], sail[0]]), Color(0.04, 0.03, 0.02, 0.8 * a), 1.5, true)
	drew_flag = true


## Whether the aim's marks (the line, the crosshair, a weak point lighting) are shown: with "Always aim at the mouse" as ever, with "Right button
## aims" only while the right button (or Shift) is held (round 22).
func _aim_marks() -> bool:
	return not main.has_method("aim_shown") or bool(main.aim_shown())


## The distance from a point to the line the avatar's shot travels along (-1 when the point is behind them).
func _aim_miss(sim, me, point: Vector2) -> float:
	var from: Vector2 = sim.avatar.shoulder(me)
	var dir := Vector2.from_angle(float(me.aim))
	var rel := point - from
	if rel.dot(dir) < 0.0:
		return -1.0
	return absf(rel.cross(dir))


## The plated brutes of a Big Night: steel on the body, and a ring at the weak point (the head's disc of the rules, `plated.weak_r` x size
## across, never under WEAK_MIN_PX on screen). The ring is quiet while the avatar aims elsewhere, lit when the aim passes within WEAK_NEAR
## radii of it (with the words "weak point"), and full when the shot would land on it: when `Avatar.trace` of the aim, the very function the
## pellets use, hits THIS brute on the head (round 19 fix: the ring promised hits the trace refused; and a melee weapon, which has no weak
## point, never fills it). A dead one wears nothing.
func _draw_plated(sim, z: float, vp: Vector2) -> void:
	var me = sim.avatar.player() if _avatar_on(sim) else null
	var aiming: bool = me != null and not me.dead and not me.turned and not me.downed and me.away == null
	# (with "Right button aims" the weak point is quiet unless the right button is held: nothing is aimed)
	var hands_off: bool = (main.has_method("avatar_hands_off") and main.avatar_hands_off()) or not _aim_marks()
	var calm := Prefs.on("ui", "reduce_motion")
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(float(main.clock) * 7.0)
	var head_k: float = NightData.num("plated.head", 0.62)
	var weak_r: float = NightData.num("plated.weak_r", 0.2)
	var font := Fonts.cond(700)
	var view := Rect2(-120.0, -120.0, vp.x + 240.0, vp.y + 240.0)
	# what the shot would do now (once for all the brutes: the pellets' own trace along the aim, with the gun in the hand and its reach)
	var shot := {}
	if aiming and not hands_off:
		var gun: Dictionary = sim.gun_of(me)
		if not bool(gun.get("melee", false)):
			shot = sim.avatar.trace(sim.avatar.shoulder(me), float(me.aim), float(sim.reach_of(gun, me)))
	for e in sim.zombies:
		if not bool(e.plated) or e.state == "dead" or e.state == "dying":
			continue
		var zp: Vector2 = main.view_pos(e)
		if not view.has_point(_screen(zp.x, zp.y)):
			continue
		drawn_plated += 1
		_draw_plates(e, zp, z)
		var size := Art.size_of(e)
		var head := _screen(zp.x, zp.y - head_k * size)
		var r_tiles := weak_r * size
		var rpx := maxf(r_tiles * z, WEAK_MIN_PX)
		var near := false
		var on := false
		if aiming and not hands_off:
			var miss := _aim_miss(sim, me, Vector2(e.x, e.y - head_k * size))
			if miss >= 0.0:
				near = miss <= r_tiles * WEAK_NEAR
			on = not shot.is_empty() and shot.z == e and bool(shot.weak)
			near = near or on
		drew_weak_marks = true
		drawn_weak_marks += 1
		weak_marks.append({"id": drawn_weak_marks, "at": head, "r": rpx, "near": near, "on": on})
		var col := WEAK_HOT if on else WEAK
		var wide := 3.0 if near else 2.0
		if HudStage.minimal_on(main):
			wide = 4.0 if on else wide    # (HUD8: a ring that points does not cover: the minimal HUD lights the weak point by its line, not by a disc over the head)
		elif on:
			draw_circle(head, rpx, Color(col, 0.28 + 0.2 * pulse))
		elif near:
			draw_circle(head, rpx, Color(col, 0.12))
		draw_arc(head, rpx, 0.0, TAU, 28, Color(0.04, 0.03, 0.02, 0.85), wide + 2.0, true)
		draw_arc(head, rpx, 0.0, TAU, 28, Color(col, 1.0 if near else 0.75), wide, true)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(head + dir * (rpx + 1.0), head + dir * (rpx + (7.0 if near else 4.0)), Color(col, 1.0 if near else 0.75), 2.0, true)
		if near:
			_tag(head + Vector2(0.0, -rpx - 16.0), "weak point", font, INK, Color(WEAK.darkened(0.65), 0.92), Color(col, 0.9))


## A breach that is hot (the nights module says: fallen, with the dead at it): a pulsing ring and "no mending under fire" under it, so that
## the player knows nobody will go to it until the dead are put down or he comes.
func _draw_hot_breaches(sim, z: float, vp: Vector2) -> void:
	if not _avatar_on(sim):
		return
	var nights = sim.get("nights")
	if nights == null or not bool(nights.active()):
		return
	var calm := Prefs.on("ui", "reduce_motion")
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(float(main.clock) * 5.0)
	var font := Fonts.cond(700)
	var view := Rect2(-60.0, -60.0, vp.x + 120.0, vp.y + 120.0)
	for seg in sim.segments:
		if seg.state != 3 or not bool(nights.breach_hot(seg)):
			continue
		var c := _screen(seg.center.x, seg.center.y)
		if not view.has_point(c):
			continue
		drew_hot_breach = true
		drawn_hot_breach += 1
		var r := clampf(z * 1.6, 26.0, 80.0)
		draw_circle(c, r, Color(HOT, 0.10 + 0.08 * pulse))
		draw_arc(c, r, 0.0, TAU, 40, Color(0.05, 0.02, 0.02, 0.8), 5.0, true)
		draw_arc(c, r, 0.0, TAU, 40, Color(HOT, 0.65 + 0.35 * pulse), 3.0, true)
		draw_arc(c, r + 4.0 + pulse * 6.0, 0.0, TAU, 40, Color(HOT, 0.5 * (1.0 - pulse)), 2.0, true)
		var text := "no mending under fire"
		var at := Vector2(clampf(c.x, 90.0, maxf(90.0, vp.x - 90.0)), c.y + r + 16.0)
		_tag(at, text, font, INK, Color(HOT.darkened(0.65), 0.92), Color(HOT, 0.9))
		hot_tags.append({"id": int(seg.id), "text": text, "at": at})


## The marks of the gate (round 22, avatar mode, `sim.gate`): near the lever, or with the gate held open as the day ends, the gateway's box is
## dashed faintly (gold and with "held open" while it is held open in the last hour before the bell) and the lever has a faint ring; and in the dark, while the leaves are
## not all the way shut, the gateway's ring is red and pulses: an open gate at night is a way in, whoever opened it.
func _draw_gate(sim, z: float, vp: Vector2) -> void:
	if not _avatar_on(sim):
		return
	var g = GateKit.active_gate(sim)
	if g == null:
		return
	var way := GateKit.gateway_of(g)
	if way.size == Vector2.ZERO:
		return
	var spot := GateKit.spot_of(g)
	var me = sim.avatar.player()
	var near := false
	if me != null and not me.dead and not me.turned and me.away == null and spot != Vector2.INF:
		near = Vector2(me.x, me.y).distance_to(spot) <= GATE_NEAR
	# held open as the day ends (the last hour before the bell, and after it): the reminder the lever's tip is about
	var held_open := GateKit.held_of(g) == "open" and (String(sim.phase) != "day" or float(sim.hour) >= float(sim.seasons.dusk_hour()) - GATE_REMIND_H)
	var breach := GateKit.is_ajar(g) and bool(sim.is_night())
	if not (near or held_open or breach):
		return
	var a := _screen(way.position.x, way.position.y)
	var b := _screen(way.end.x, way.end.y)
	var box := Rect2(a, b - a).abs()
	if not Rect2(-60.0, -60.0, vp.x + 120.0, vp.y + 120.0).intersects(box):
		return
	gate_box = box
	var calm := Prefs.on("ui", "reduce_motion")
	var pulse := 0.5 if calm else 0.5 + 0.5 * sin(float(main.clock) * 5.0)
	if breach:
		drew_gate_pulse = true
		var r := minf(14.0, box.size.y * 0.5)
		var ring := S.closed(S.rrect(box.position.x, box.position.y, box.size.x, box.size.y, r, 5))
		draw_colored_polygon(S.rrect(box.position.x, box.position.y, box.size.x, box.size.y, r, 5), Color(HOT, 0.08 + 0.08 * pulse))
		draw_polyline(ring, Color(0.05, 0.02, 0.02, 0.8), 5.0, true)
		draw_polyline(ring, Color(HOT, 0.65 + 0.35 * pulse), 3.0, true)
		var grow := 4.0 + pulse * 6.0
		var halo := box.grow(grow)
		draw_polyline(S.closed(S.rrect(halo.position.x, halo.position.y, halo.size.x, halo.size.y, r + grow, 5)), Color(HOT, 0.5 * (1.0 - pulse)), 2.0, true)
		gate_tag = "gate held open" if GateKit.held_of(g) == "open" else "gate open"
		_gate_words = {"text": gate_tag, "color": INK, "back": Color(HOT.darkened(0.65), 0.92), "ring": Color(HOT, 0.9)}
	else:
		drew_gate_outline = true
		var col := Color(ACCENT, 0.8) if held_open else Color(GATE_OUTLINE, GATE_FAINT)
		var tl := box.position
		var br := box.end
		for edge in [[tl, Vector2(br.x, tl.y)], [Vector2(br.x, tl.y), br], [br, Vector2(tl.x, br.y)], [Vector2(tl.x, br.y), tl]]:
			_dashed_line(edge[0], edge[1], col, 2.0)
		if held_open:
			gate_tag = "held open"
			_gate_words = {"text": gate_tag, "color": ACCENT, "back": PROMPT_BACK, "ring": Color(ACCENT, 0.7)}
	if spot != Vector2.INF:
		# the lever: a faint ring where the hand goes (the prompt's own ring is drawn over it)
		drew_gate_spot = true
		var c := _screen(spot.x, spot.y)
		var rx := clampf(z * 0.6, 14.0, 70.0)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 40, Color(GATE_OUTLINE, GATE_FAINT), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The floating word over the lever (round 23, avatar mode): "GATE (E)" while the avatar is up and inside the walls within LABEL_R tiles of it, so that
## the way to the gate is never a thing to find; it gives way to the prompt's own pill when that is on the gate, and it is not under a board of the HUD.
func _draw_gate_label(sim, z: float, vp: Vector2) -> void:
	if not _avatar_on(sim):
		return
	var g = GateKit.active_gate(sim)
	if g == null:
		return
	var spot := GateKit.spot_of(g)
	var me = sim.avatar.player()
	if spot == Vector2.INF or me == null or me.dead or me.turned or me.away != null or me.downed:
		return
	var reach = g.get("LABEL_R")
	var limit := float(reach) if reach != null else 12.0
	if Vector2(me.x, me.y).distance_to(spot) > limit:
		return
	if g.has_method("outside_by") and float(g.outside_by(Vector2(me.x, me.y))) > 0.0:
		return    # (the lever is on the inside of the wall)
	var asked := prompt_candidate()
	if String(asked.get("kind", "")) == "gate":
		return
	var c := _screen(spot.x, spot.y)
	var font := Fonts.cond(700)
	var text := "GATE (E)"
	var at := Vector2(c.x, c.y - clampf(z * 1.15, 40.0, 110.0))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 10.0
	var r := Rect2(at.x - tw / 2.0, at.y - 8.0, tw, 16.0)
	if not Rect2(4.0, 4.0, vp.x - 8.0, vp.y - 8.0).encloses(r) or _under_hud(r, _covered_by_hud()):
		return
	_tag(at, text, font, ACCENT, PROMPT_BACK, Color(ACCENT, 0.85))
	drew_gate_label = true
	gate_label_rect = r


## Puts the gate's words by the gateway (after the prompt is down: they keep clear of its pill, of the HUD's boards and of the window's edge): under
## the box in the middle, else under its right end, inside its right end at the foot, else over the box. Not drawn when there is no such place.
func _draw_gate_tag(vp: Vector2) -> void:
	if _gate_words.is_empty() or gate_box.size == Vector2.ZERO:
		return
	var font := Fonts.cond(700)
	var text := String(_gate_words.text)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_PX).x + 10.0
	var box := gate_box
	var at_x := clampf(box.get_center().x, 90.0, maxf(90.0, vp.x - 90.0))
	var spots := [
		Vector2(at_x, box.end.y + 16.0),
		Vector2(clampf(box.end.x - tw / 2.0, tw / 2.0 + 4.0, maxf(tw / 2.0 + 4.0, vp.x - tw / 2.0 - 4.0)), box.end.y + 16.0),
		Vector2(clampf(box.end.x - tw / 2.0 - 6.0, tw / 2.0 + 4.0, maxf(tw / 2.0 + 4.0, vp.x - tw / 2.0 - 4.0)), box.end.y - 14.0),
		Vector2(at_x, box.position.y - 14.0),
	]
	var view := Rect2(4.0, 4.0, vp.x - 8.0, vp.y - 8.0)
	var covered := _covered_by_hud()
	for c in spots:
		var r := Rect2(c.x - tw / 2.0, c.y - 8.0, tw, 16.0)
		if not view.encloses(r) or _under_hud(r, covered) or (prompt_rect.size != Vector2.ZERO and prompt_rect.grow(4.0).intersects(r)):
			continue
		_tag(c, text, font, _gate_words.color, _gate_words.back, _gate_words.ring)
		drew_gate_tag = true
		gate_tag_rect = r
		return


## What the avatar's hands are doing at a wall (round 19): the session is the nights' module's (`sim.nights`: `working` is "wall" while
## mending, `work_left` the rules seconds left of `mend.seconds`, `mend_seg` the section; round 18's E starts and stops it through
## `Interact.use`): {"on": whether they are mending, "progress": 0 to 1, "seg": the section's id (-1 for none)}. A sim with no such module,
## or hands at the bench (`sim.interact.working`), is {"on": false}.
static func mend_state(sim) -> Dictionary:
	var n = sim.get("nights")
	if n == null or String(n.get("working")) != "wall":
		return {"on": false, "progress": 0.0, "seg": -1}
	var total: float = maxf(0.01, NightData.num("mend.seconds", 10.0))
	return {"on": true, "progress": clampf(1.0 - float(n.get("work_left")) / total, 0.0, 1.0), "seg": int(n.get("mend_seg"))}


## The ring round the avatar while their hands mend a wall (the bench's ring, for the wall): it fills as the work goes.
func _draw_mend(sim, z: float) -> void:
	if not _avatar_on(sim):
		return
	var me = sim.avatar.player()
	if me == null or me.dead or me.turned or me.away != null:
		return
	var st := mend_state(sim)
	if not bool(st.on):
		return
	mend_progress = float(st.progress)
	drew_mend_ring = true
	var pp: Vector2 = main.view_pos(me)
	var c := _screen(pp.x, pp.y - 0.45)
	var r := maxf(22.0, 0.74 * z)
	draw_arc(c, r, 0.0, TAU, 40, RING_TRACK, 4.0, true)
	draw_arc(c, r, -PI / 2.0, -PI / 2.0 + mend_progress * TAU, 40, RALLY, 3.0, true)
	_tag(c + Vector2(0.0, r + 14.0), "mending", Fonts.cond(700), INK, Color(0.04, 0.07, 0.06, 0.85), Color(RALLY, 0.8))


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

## HUD8: whether the name under a person is left out (the minimal HUD only): the one she plays (the YOU tag is there), and the crew farther than `NAME_NEAR_TILES` from her.
func _name_is_quiet(p, sim) -> bool:
	if not HudStage.minimal_on(main):
		return false
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	if me == null:
		return false
	if p == me:
		return true
	return Vector2(p.x - me.x, p.y - me.y).length() > NAME_NEAR_TILES


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


## How near the avatar (tiles) a person's order still shows over their head, as the person picked's always does.
const STANCE_NEAR := 12.0
## What the last frame drew of them (a test reads it): pills and dotted lines.
var drawn_stance_marks := 0
var drawn_stance_links := 0
var stance_people: Array = []
var stance_kinds := PackedStringArray()


## Round 24 (scripts/render/stance_marks.gd): a glyph pill over the head of each person who carries an order of the radio (following, holding, covering,
## searching, walking to a post) and a thin dotted line from them to the spot of a hold, a search or a post; for the person picked and for everyone within
## STANCE_NEAR tiles of the avatar. A few draw calls each (a stylebox, a glyph, a dashed line), nothing made in the frame but those. Not in the old yard.
func _draw_stance_marks(sim, vp: Vector2) -> void:
	drawn_stance_marks = 0
	drawn_stance_links = 0
	stance_people.clear()
	stance_kinds.clear()
	if main.get("avatar_mode") != true:
		return
	var me = sim.avatar.player()
	var sel = main.selection
	var picked = sel.ref if sel != null and sel.kind == "person" else null
	for p in sim.people:
		if p.away != null or p.dead or p.turned or p == me:
			continue
		var kind := StanceMarks.of_person(p)
		if kind == "":
			continue
		if p != picked and (me == null or Vector2(p.x, p.y).distance_to(Vector2(me.x, me.y)) > STANCE_NEAR):
			continue
		var pp: Vector2 = main.view_pos(p)
		var head := _screen(pp.x, pp.y - BUBBLE_HEAD)
		if head.x < -40.0 or head.x > vp.x + 40.0 or head.y < -30.0 or head.y > vp.y + 60.0:
			continue
		var spot := StanceMarks.spot_of(p, kind)
		if spot != Vector2.INF:
			var to := _screen(spot.x, spot.y)
			var from := _screen(pp.x, pp.y)
			if from.distance_to(to) > 14.0:
				StanceMarks.draw_link(self, kind, from, to)
				drawn_stance_links += 1
		StanceMarks.draw_pill(self, kind, head + Vector2(0.0, -4.0))
		drawn_stance_marks += 1
		stance_people.append(p)
		stance_kinds.append(kind)


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
	var marks := _aim_marks()
	# the line from the gun
	if marks and not hands_off and not me.downed and not melee and me.reloading <= 0.0:
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
		_draw_shells(c, r, me, sim)
	_draw_dry(me, pp, z)
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
	# the crosshair (none for one who is down: there is nothing in their hands, nor with a free pointer)
	if not marks or hands_off or me.downed or bool(main.get("over_hud")):
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


## A gun that loads a shell at a time (the pump shotgun, the hunting rifle, the M1: a few rounds in the magazine) shows each shell on the reload ring:
## a mark between two and a pip on each stretch of the ring, brass when its shell is in (combat_fx.gd `reload_view` says how many are in; the
## rules fill the magazine at the end of the time, the pips and the click of each shell are the picture and the sound of it).
func _draw_shells(c: Vector2, r: float, me, sim) -> void:
	var fx = main.get("fx")
	if fx == null or fx.get("combat") == null:
		return
	var rv: Dictionary = fx.combat.reload_view(me, sim)
	var n := int(rv.get("notches", 0))
	if n <= 0:
		return
	var filled := int(rv.get("filled", 0))
	for k in n:
		var a0 := -PI / 2.0 + TAU * float(k) / float(n)
		var am := -PI / 2.0 + TAU * (float(k) + 0.5) / float(n)
		draw_line(c + Vector2.from_angle(a0) * (r - 5.0), c + Vector2.from_angle(a0) * (r + 5.0), RING_TRACK, 2.5, true)
		var at := c + Vector2.from_angle(am) * r
		var loaded := k < filled
		draw_circle(at, 5.5, Color(0.04, 0.07, 0.06, 0.85))
		draw_circle(at, 4.0, Color("#c9a54a") if loaded else Color(0.30, 0.30, 0.26, 0.9))
		if loaded:
			draw_rect(Rect2(at.x - 1.5, at.y - 4.0, 3.0, 2.2), Color("#b8352c"))


## The trigger pulled on an empty gun, or one being filled: a ring that flashes red round the survivor and a word that says why nothing happened
## ("empty", "reloading"), for under half a second (combat_fx.gd `dry_fire`). Under "reduce motion" it does not grow.
func _draw_dry(me, pp: Vector2, z: float) -> void:
	var fx = main.get("fx")
	if fx == null or fx.get("combat") == null or me.downed:
		return
	var age: float = fx.combat.dry_age()
	if age < 0.0 or age > 0.5:
		return
	var k := 1.0 - age / 0.5
	var calm := Prefs.on("ui", "reduce_motion")
	var c := _screen(pp.x, pp.y - 0.45)
	var r := maxf(18.0, 0.66 * z) * (1.0 if calm else 1.0 + (1.0 - k) * 0.3)
	draw_arc(c, r, 0.0, TAU, 40, Color(CROSS_HIT, 0.85 * k), 3.0, true)
	var word := String(fx.combat.dry_word).to_upper()
	if word != "":
		_tag(c + Vector2(r + 44.0, 0.0), word, Fonts.cond(700), INK, Color(0.18, 0.05, 0.04, 0.9 * k), Color(CROSS_HIT, 0.9 * k))


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
	# (Orientation Day's coach refuses what a step does not teach: E is refused there, so no pill is drawn for it)
	var coach = main.get("coach")
	if coach != null and coach.has_method("would_allow") and not coach.would_allow("interact"):
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
	var mending := mend_state(main.sim)    # (round 19: the wall being mended, E on it stops the hands)
	if bool(mending.on):
		began.append("wall:%d" % int(mending.seg))
	if String(_prop(it, "posted", "")) != "":
		began.append("post:%s" % String(_prop(it, "posted", "")))
	var pm = main.sim.get("problems")
	var fixing = pm.get("fixing") if pm != null else null
	if fixing is Dictionary and not (fixing as Dictionary).is_empty():
		began.append("problem:%s" % String(fixing.get("id", "")))    # (round 25: the fix in hand: E is to end it, whoever stands as near)
	var list := started_first(it.candidates(), began)
	var pick := choose_prompt(list, prompt_key)
	# (round 22, "Right button aims": the thing under the free pointer is the one the pill is on, so E does what a click would)
	var under := _pointed_candidate(list)
	if not under.is_empty():
		pick = under
	prompt_key = key_of(pick)
	return pick


## The candidate of `list` the free pointer is over (a person's, a thing's that is in reach), or {}.
func _pointed_candidate(list: Array) -> Dictionary:
	var pt = main.get("pointed")
	if not (pt is Dictionary) or pt.is_empty():
		return {}
	if String(pt.get("kind", "")) == "person":
		for c in list:
			if String(c.get("kind", "")) == "person" and String(c.get("id", "")) == String(pt.ref.id):
				return c
		return {}
	if bool(pt.get("near", false)):
		return WorldClick.listed(pt.cand, list)
	return {}


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
	# WORLD: the claim takes two seconds of standing still at the door: the pill says so ("hold"), and a thing that takes time carries the ring of its session
	if kind == "claim" and label == "Claim this house":
		label = "Hold to claim"
	elif kind == "claim" and label == "Stop":
		label = "Stop claiming"
	var timed := bool(c.get("session", false))
	var ring: Dictionary = PromptKit.session_ring(main.get("sim") if main != null else null, c) if timed else {}
	if ok:
		why = ""
	return {"label": label, "why": why, "ok": ok, "timed": timed, "ring": ring, "text": "E  %s" % label if why == "" else "E  %s: %s" % [label, why]}


## Where the thing a candidate is on is on the screen (pixels): a person at their feet as drawn, anything else where the rules say.
func _spot_of(c: Dictionary) -> Vector2:
	if String(c.get("kind", "")) == "person":
		var who = _person(String(c.get("id", "")))
		if who != null:
			var pp: Vector2 = main.view_pos(who)
			return _screen(pp.x, pp.y)
	var at: Vector2 = c.get("pos", Vector2.ZERO)
	if String(c.get("kind", "")) == "gate" and at == Vector2.ZERO:
		# (the gate's candidate is the lever: where the rules put the control point, when the candidate does not say)
		var lever := GateKit.spot_of(GateKit.active_gate(main.sim))
		if lever != Vector2.INF:
			at = lever
	return _screen(at.x, at.y)


## The base's trouble on the world (round 25, scripts/render/base_marks.gd): the markers of the open problems with their words and their time, the
## quarantine's sign, the labels of the stations that wait on something and the ring of the avatar's hands at a fix. The yard only: nothing in a
## place, under a modal or without an avatar. A view: the rules' words, nothing of its own.
func _draw_base(sim, z: float, vp: Vector2) -> void:
	drew_problem_marks = false
	drawn_problem_marks = 0
	drawn_problem_labels = 0
	drew_facility_labels = false
	drawn_facility_labels = 0
	drew_fix_ring = false
	fix_progress = 0.0
	if not _avatar_on(sim) or _modal_open() or (main.has_method("raid_open") and main.raid_open()):
		base_marks.clear()
		return
	if not _screen_cb.is_valid():
		_screen_cb = Callable(self, "_screen_at")
		_base_opts["covered"] = Callable(self, "_covered_by_hud")
	var me = sim.avatar.player()
	var at := Vector2.INF
	if me != null and not me.dead and not me.turned and me.away == null:
		at = main.view_pos(me)
	var hud = main.get("hud")
	_base_opts["z"] = z
	_base_opts["vp"] = vp
	_base_opts["clock"] = float(main.clock)
	_base_opts["calm"] = Prefs.on("ui", "reduce_motion")
	_base_opts["me"] = at
	_base_opts["base_page"] = hud != null and hud.has_method("radio_page") and String(hud.radio_page()) == "base"
	base_marks.draw(self, sim, _screen_cb, _base_opts)
	drawn_problem_marks = base_marks.drawn_marks
	drawn_problem_labels = base_marks.drawn_labels
	drew_problem_marks = drawn_problem_marks > 0
	drawn_facility_labels = base_marks.drawn_facilities
	drew_facility_labels = drawn_facility_labels > 0
	drew_fix_ring = base_marks.fix_ring
	fix_progress = base_marks.fix_progress


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
	# a thing under the free pointer that is out of reach (round 22): a dim ring and what a click would say
	var pt = main.get("pointed")
	if pt is Dictionary and String(pt.get("kind", "")) == "thing" and not bool(pt.get("near", true)) and not _modal_open():
		var far_spot := _spot_of(pt.cand)
		var far_rx := clampf(z * (1.1 if String(pt.cand.get("kind", "")) == "vehicle" else 0.55), 14.0, 70.0)
		draw_set_transform(far_spot, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, far_rx, 0.0, TAU, 40, Color(PILL, 0.6), 4.5, true)
		draw_arc(Vector2.ZERO, far_rx, 0.0, TAU, 40, Color(Hud.INK3, 0.85), 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var far_text := WorldClick.TOO_FAR
		if String(pt.cand.get("kind", "")) == "gate":
			# (round 23: the gate's picture is a click from CLICK_REACH tiles, E from REACH)
			far_text = ("Click: %s" % String(pt.cand.get("label", "Open the gate")).to_lower()) if bool(pt.get("click_ok", false)) else WorldClick.TOO_FAR_GATE
		_tag(far_spot + Vector2(0.0, -far_rx * 0.5 - 22.0), far_text, Fonts.cond(700), Hud.INK2, PROMPT_BACK, Color(Hud.INK3, 0.7))
		drew_far_tag = true
	# the prompt
	var c := prompt_candidate()
	if c.is_empty():
		_draw_searched_stand_in(z, vp)
		return
	var words := prompt_for(c, it)
	prompt_text = String(words.text)
	prompt_ok = bool(words.ok)
	var spot := _spot_of(c)
	var kind := String(c.kind)
	var rx := clampf(z * (1.1 if kind == "vehicle" else (0.7 if kind == "bench" else (0.8 if kind == "problem" else (0.6 if kind == "wall" or kind == "gate" else 0.5)))), 14.0, 70.0)
	var ring: Color = ACCENT if prompt_ok else Hud.INK3
	# the thing under the free pointer (round 22): a wider, brighter ring
	var hovered := not _pointed_candidate([c]).is_empty()
	if hovered:
		drew_hover_ring = true
		hover_key = key_of(c)
	# (the post that is held has its own green ring: the steady stance; a problem has its pulsing marker on the ground: the pill sits clear of it, and only
	# the pointer over it draws this ring)
	if not (kind == "post" and String(_prop(it, "posted", "")) == String(c.id)) and (kind != "problem" or hovered):
		draw_set_transform(spot, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, rx * (1.18 if hovered else 1.0), 0.0, TAU, 40, Color(PILL, 0.75 if hovered else 0.65), 6.0 if hovered else 4.5, true)
		draw_arc(Vector2.ZERO, rx * (1.18 if hovered else 1.0), 0.0, TAU, 40, Color(ring, 1.0 if hovered else ((0.6 + 0.4 * pulse) if prompt_ok else 0.6)), 3.5 if hovered else 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_prompt_pill(words, spot, rx, vp)


## The pill of the prompt: a gold key with E, the label, and for a refusal the reason in amber under it; beside the ring on the right,
## else on the left, else above, else below, whichever is in the window and not under a board of the HUD. Not drawn when none is.
func _draw_prompt_pill(words: Dictionary, spot: Vector2, rx: float, vp: Vector2) -> void:
	var font := Fonts.sans(600)
	var fs := maxi(FIELD_PX, Fonts.MIN_PX)
	var label := String(words.label)
	var why := String(words.why)
	# WORLD: the key is a cap (scripts/render/prompt_kit.gd); a thing that takes time has the ring round it, and the seconds left are said after the words
	var stub: bool = bool(words.get("stub", false))
	var ring: Dictionary = words.get("ring", {})
	var timed: bool = bool(words.get("timed", false)) and bool(words.get("ok", true)) and not stub
	var area := PromptKit.AREA_RING if timed else PromptKit.AREA
	var left_txt := ("%ds" % ceili(float(ring.left))) if not ring.is_empty() and float(ring.get("left", 0.0)) > 0.0 else ""
	var left_w := (font.get_string_size(left_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0) if left_txt != "" else 0.0
	var inner := PROMPT_MAX_W - area - 24.0
	var label_w := minf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, inner)
	var why_w := minf(font.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, inner, fs).x, inner) if why != "" else 0.0
	var lines := 2 if why != "" else 1
	var h := (44.0 if timed else 32.0) if lines == 1 else 48.0
	var w := 6.0 + area + 6.0 + maxf(label_w + left_w, why_w) + 12.0
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
	# (HUD8, the placement rule: first a side that is over none of the dead in view; a prompt the player needs is never dropped for it, and if every side has one the first as it was)
	var dead: Array = HudStage.dead_rects(main, 0.4)
	for pass_i in 2:
		for at in sides:
			var r := Rect2(at, Vector2(w, h))
			if view.encloses(r) and not _under_hud(r, covered) and (pass_i == 1 or not HudStage._touches(r, dead)):
				rect = r
				found = true
				break
		if found:
			break
	if not found:
		return
	var ok: bool = bool(words.get("ok", prompt_ok)) if stub else prompt_ok
	var round_r := minf(14.0, rect.size.y * 0.5)
	draw_colored_polygon(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, round_r, 5), PROMPT_BACK)
	draw_polyline(S.closed(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, round_r, 5)), Color(ACCENT if ok else Hud.INK3, 0.8 if not stub else 0.45), 1.5, true)
	var cap_at := Vector2(rect.position.x + 6.0 + area * 0.5, rect.position.y + rect.size.y * 0.5)
	PromptKit.draw_cap(self, cap_at, ok, "check" if stub else "E", fs, timed, ring)
	var tx := rect.position.x + 6.0 + area + 6.0
	var base_y := rect.position.y + rect.size.y * 0.5 + fs * 0.36 if lines == 1 else rect.position.y + 7.0 + fs
	draw_string(font, Vector2(tx, base_y), label, HORIZONTAL_ALIGNMENT_LEFT, inner, fs, Hud.INK if ok else Hud.INK2)
	if left_txt != "":
		draw_string(font, Vector2(tx + label_w + 8.0, base_y), left_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Hud.INK3)
	if why != "":
		draw_string(font, Vector2(tx, rect.position.y + 26.0 + fs), why, HORIZONTAL_ALIGNMENT_LEFT, inner, fs, Hud.WARN)
	if stub:
		drew_searched = true
		return
	prompt_ring = float(ring.t) if not ring.is_empty() else -1.0
	prompt_rect = rect
	drew_prompt = true


## WORLD: a container the avatar has already searched has nothing to press: its pill is the grey "Searched" with a check mark where the key would be, drawn only when there is
## no real prompt (the rules offer no candidate for a looted container). The place comes from the search marks part (scripts/ui/search_marks.gd).
func _draw_searched_stand_in(z: float, vp: Vector2) -> void:
	if not _prompt_allowed():
		return
	var town = main.get("town")
	var marks = town.part("search_marks") if town != null and town.has_method("part") else null
	if marks == null or not marks.has_method("searched_near"):
		return
	var near: Dictionary = marks.searched_near()
	if near.is_empty():
		return
	var spot := _screen(float(near.at.x), float(near.at.y))
	_draw_prompt_pill({"label": "Searched", "why": "", "ok": false, "stub": true, "timed": false, "ring": {}}, spot, clampf(z * 0.5, 14.0, 70.0), vp)


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
	prompt_ring = -1.0
	drew_searched = false
	drew_hover_ring = false
	hover_key = ""
	drew_far_tag = false
	prompt_text = ""
	prompt_rect = Rect2()
	drew_brace = false
	drew_bench_ring = false
	aim_on_target = false
	drew_target_marks = false
	drawn_target_marks = 0
	target_tags = []
	target_lit = false
	drew_rally_ring = false
	rally_lit = false
	drawn_rallied = 0
	drew_weak_marks = false
	drawn_weak_marks = 0
	drawn_plated = 0
	weak_marks = []
	drew_hot_breach = false
	drawn_hot_breach = 0
	hot_tags = []
	drew_mend_ring = false
	drew_gate_outline = false
	drew_gate_pulse = false
	drew_gate_spot = false
	gate_tag = ""
	gate_box = Rect2()
	drew_gate_tag = false
	gate_tag_rect = Rect2()
	drew_gate_label = false
	gate_label_rect = Rect2()
	_gate_words = {}
	if main.fields:
		_draw_fields(sim, z, vp)
	_draw_alarm(sim, z, vp)
	_draw_jobs(sim, z, vp)
	_draw_targets(sim, z, vp)

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
	_draw_order_flag(z)

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
			if not selected and _name_is_quiet(p, sim):
				pass    # (HUD8: the minimal HUD names the crew within 6 tiles of her, and a person who is picked; the YOU tag says who she is)
			else:
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

	# round 24: what the player has asked of people over the radio, over their heads (and the dotted line to the spot)
	_draw_stance_marks(sim, vp)

	# the nights' marks: the ring of the rally, the plated brutes and their weak points, the breaches that are hot
	_draw_rally(sim, z, vp)
	_draw_hot_breaches(sim, z, vp)
	_draw_plated(sim, z, vp)
	_draw_gate(sim, z, vp)
	_draw_gate_label(sim, z, vp)
	# the base's trouble: the markers, the quarantine's sign, the stations' labels (round 25)
	_draw_base(sim, z, vp)

	# the avatar's marks: the aim line, the reload ring, the YOU tag and the crosshair
	_draw_avatar(sim, z, vp)
	# what E would do: the prompt, the steady stance, the bench's ring
	_draw_interact(sim, z, vp)
	_draw_gate_tag(vp)
	_draw_mend(sim, z)

	# what people say, over everything else
	_draw_bubbles(vp)
