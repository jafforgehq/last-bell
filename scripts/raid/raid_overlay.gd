## What the raid draws over its world, at screen size (round 14, R14.3; the one survivor, round 17, S1.6b): the exit's outline,
## a mark on each container (a ring while it is still to search, a progress ring while someone searches it, a tick once it is
## looted) and a prompt on the one in reach of E, a ring under each of the squad and a mark over the one you lead ("YOU"), a
## name and a health bar and what they are doing under each of them, a red mark over the dead who hunt, a flag where someone was
## told to hold or to search, the marks the radio leaves, the reload ring about the one you lead, the aim line from the muzzle
## and the crosshair at the pointer. All of it is a view: nothing here changes the rules. Lives on a CanvasLayer of the scene
## (raid_scene.gd), which it reads.
extends Node2D

const Fonts := preload("res://scripts/ui/fonts.gd")
const S := preload("res://scripts/render/shapes.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")

const ACCENT := Color(0.941, 0.761, 0.29)
const INK := Color("#eeeadd")
const PILL := Color(11 / 255.0, 20 / 255.0, 17 / 255.0, 0.8)
const OK := Color("#8fb85a")
const INFO := Color("#7fa6c9")
const DANGER := Color("#e0584a")
const WARN := Color("#e6a23c")
## Nothing is drawn smaller than the HUD's floor for text.
const NAME_PX := 13
## The words of what someone does that are worth a tag under them in the world.
const SHOWN_STATUS := ["Holding", "Covering", "Searching", "Going to search", "Heading back", "Down", "Helping", "Going to help"]
## The crosshair's arms and the least its ring is.
const CROSS_ARM := 7.0
const CROSS_GAP := 4.0
const RING_MIN := 9.0

var scene
## What the last draw put on the screen (for the tests).
var drawn_containers := 0
var drawn_names := 0
var drawn_hunters := 0
var drawn_crosshair := false
var drawn_aim_line := false
var drawn_reload_ring := false
var drawn_prompt := ""


func _pill(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(S.rrect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, rect.size.y * 0.5, 5), color)


func _dashed_circle(c: Vector2, r: float, color: Color, width: float) -> void:
	var n := maxi(12, int(TAU * r / 10.0))
	for i in n:
		var a0 := TAU * i / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.4, 4, color, width, true)


func _dashed_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dist := a.distance_to(b)
	if dist < 1.0:
		return
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
	if scene == null or scene.run == null or scene.phase != "place":
		return
	var run = scene.run
	var z: float = scene.zoom_px
	var vp := get_viewport_rect().size
	var screen := Rect2(Vector2(-60, -60), vp + Vector2(120, 120))
	var font := Fonts.cond(600)
	var lead = scene.leader()
	drawn_containers = 0
	drawn_names = 0
	drawn_hunters = 0
	drawn_crosshair = false
	drawn_aim_line = false
	drawn_reload_ring = false
	drawn_prompt = ""

	# the way out: a dashed outline, so the squad knows where "back" is (lit while the one you lead stands in it)
	var ex: Rect2 = run.site.exit
	var a: Vector2 = scene.to_screen(ex.position)
	var b: Vector2 = scene.to_screen(ex.end)
	var lit: bool = lead != null and ex.has_point(Vector2(lead.x, lead.y))
	var ex_col := Color(OK, 0.95 if lit else 0.55)
	for edge in [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b], [b, Vector2(a.x, b.y)], [Vector2(a.x, b.y), a]]:
		_dashed_line(edge[0], edge[1], ex_col, 2.0 if lit else 1.5)
	if screen.has_point(a):
		_tag(a + Vector2(30.0, -12.0), "Exit", font, INK, Color(OK.darkened(0.55), 0.9))

	# the containers
	var reach: Dictionary = scene.reach_container
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
		var in_reach: bool = not reach.is_empty() and String(reach.id) == String(c.id)
		if progress > 0.0:
			draw_arc(at, r, 0, TAU, 32, Color(PILL, 0.8), 5.0, true)
			draw_arc(at, r, -PI / 2.0, -PI / 2.0 + progress * TAU, 32, ACCENT, 3.5, true)
		elif in_reach:
			draw_arc(at, r, 0, TAU, 32, Color(ACCENT, 0.95), 3.0, true)
		else:
			_dashed_circle(at, r, Color(ACCENT, 0.85), 2.0)
		if in_reach:
			var searching: bool = lead != null and run.searching_of(lead) == String(c.id)
			var words := "%s: searching, E to stop" % String(c.kind).capitalize() if searching else "E  Search the %s (%d s)" % [String(c.kind), int(ceilf(float(c.search_s)))]
			drawn_prompt = words
			_tag(at + Vector2(0.0, -r - 14.0), words, font, ACCENT if not searching else INK)

	# a friend who is down within reach: the prompt to get them up, and the progress while it goes
	var friend = scene.reach_friend
	if friend != null and lead != null:
		var fp: Vector2 = scene.to_screen(scene.view_pos(friend) + Vector2(0.0, -0.3))
		var h: Dictionary = run.get("_helping").get(String(lead.id), {}) if run.get("_helping") != null else {}
		var helping: bool = not h.is_empty()
		if helping:
			var k := clampf(float(h.t) / RaidRun.HELP_S, 0.0, 1.0)
			var hr := clampf(0.7 * z, 12.0, 44.0)
			draw_arc(fp, hr, 0, TAU, 32, Color(PILL, 0.8), 5.0, true)
			draw_arc(fp, hr, -PI / 2.0, -PI / 2.0 + k * TAU, 32, INFO, 3.5, true)
		var words2 := "Getting %s up: E to stop" % String(friend.first) if helping else "E  Help %s up (%d s)" % [String(friend.first), int(RaidRun.HELP_S)]
		drawn_prompt = words2
		_tag(fp + Vector2(0.0, -1.75 * z), words2, font, INFO if helping else INK)    # (above the "YOU" tag of whoever stands beside them)

	# the squad: a ring under each (gold for the one you lead)
	for p in run.squad:
		if p.dead:
			continue
		var pp: Vector2 = scene.view_pos(p)
		var foot: Vector2 = scene.to_screen(pp)
		var you: bool = p == lead
		var rw := 0.42 * z
		draw_set_transform(foot, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, rw, 0, TAU, 28, ACCENT if you else Color(INK, 0.45), 2.5 if you else 1.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var picked: bool = scene.is_selected(p)
		if picked:
			var ta: Vector2 = scene.to_screen(Vector2(pp.x - 0.48, pp.y - 0.92))
			var tb: Vector2 = scene.to_screen(Vector2(pp.x + 0.48, pp.y + 0.42))
			var L := maxf(5.0, (tb.x - ta.x) * 0.22)
			for k in [[ta.x, ta.y, 1, 1], [tb.x, ta.y, -1, 1], [ta.x, tb.y, 1, -1], [tb.x, tb.y, -1, -1]]:
				draw_polyline(PackedVector2Array([Vector2(k[0] + k[2] * L, k[1]), Vector2(k[0], k[1]), Vector2(k[0], k[1] + k[3] * L)]), INFO, 2.0, true)
		if you and not p.downed:
			var head_at: Vector2 = scene.to_screen(Vector2(pp.x, pp.y - 1.15))
			if screen.has_point(head_at):
				_tag(head_at, "YOU", font, Color("#1a1508"), Color(ACCENT, 0.95))
			# the reload ring about their head
			if p.reloading > 0.0:
				var total := maxf(float(p.gun.get("reload", 1.0)), 0.1)
				var k2 := clampf(1.0 - float(p.reloading) / total, 0.0, 1.0)
				var rc: Vector2 = scene.to_screen(Vector2(pp.x, pp.y - 0.5))
				draw_arc(rc, 0.72 * z, 0, TAU, 32, Color(PILL, 0.7), 4.0, true)
				draw_arc(rc, 0.72 * z, -PI / 2.0, -PI / 2.0 + k2 * TAU, 32, WARN, 3.0, true)
				drawn_reload_ring = true

	# where someone was told to hold or to search: a flag
	for p in run.squad:
		if p.dead or p.downed:
			continue
		var stance := String(p.stance)
		if (stance == "hold" or stance == "search") and p.stance_at != Vector2.ZERO:
			var at2: Vector2 = scene.to_screen(p.stance_at)
			if screen.has_point(at2):
				_dashed_circle(at2, 0.4 * z, Color(INFO if stance == "hold" else OK, 0.8), 1.8)
				draw_line(at2, at2 + Vector2(0.0, -0.8 * z), Color(INFO if stance == "hold" else OK, 0.9), 2.0, true)

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

	# the marks the radio leaves
	for m in scene.marks:
		var k3: float = clampf((scene.clock - float(m.t)) / 0.8, 0.0, 1.0)
		if k3 >= 1.0:
			continue
		var col := INFO if m.kind == "hold" else (OK if m.kind == "search" or m.kind == "exit" else ACCENT)
		draw_arc(scene.to_screen(Vector2(m.x, m.y)), (0.2 + k3 * 0.55) * z, 0, TAU, 32, Color(col, 1.0 - k3), 2.5, true)

	# names, health and what they are doing, under the squad
	if z >= 14.0:
		for p in run.squad:
			var pp2: Vector2 = scene.view_pos(p)
			var pos: Vector2 = scene.to_screen(Vector2(pp2.x, pp2.y + 0.52))
			if not screen.has_point(pos):
				continue
			drawn_names += 1
			var you2: bool = p == lead
			var picked2: bool = scene.is_selected(p)
			var label: String = p.first
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_PX).x + 10.0
			var bg := Color(ACCENT, 0.92) if (you2 or picked2) else (Color(12 / 255.0, 22 / 255.0, 19 / 255.0, 0.74))
			_pill(Rect2(pos.x - tw / 2.0, pos.y - 9.0, tw, 18.0), bg)
			draw_string(font, Vector2(pos.x - tw / 2.0, pos.y + NAME_PX * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, tw, NAME_PX, Color("#1a1508") if (you2 or picked2) else INK)
			var row := 11.0
			if p.hp < 100.0 and not p.dead:
				draw_rect(Rect2(pos.x - 14, pos.y + row, 28, 4), PILL)
				draw_rect(Rect2(pos.x - 13.5, pos.y + row + 0.5, 27.0 * clampf(p.hp / 100.0, 0.0, 1.0), 3), Color("#d0493a") if p.hp < 35.0 else Color("#8fb85a"))
				row += 8.0
			if not you2 and z >= 22.0:
				var word: String = scene.status_of(p)
				# (only what they were asked to do, or what is wrong: "Fighting" and "Following" are not worth a tag each)
				if SHOWN_STATUS.has(word):
					_tag(pos + Vector2(0.0, row + 8.0), word, font, Hud.INK2 if word != "Down" else DANGER, Color(PILL, 0.6))

	# the aim line from the muzzle toward the pointer, as far as the gun reaches
	if lead != null and not lead.downed and scene.crosshair_shown():
		var lp: Vector2 = scene.view_pos(lead)
		var muzzle: Vector2 = scene.to_screen(Vector2(lp.x, lp.y - 0.5))
		var target: Vector2 = scene._mouse
		var reach_px: float = float(run.sim.reach_of(lead.gun, lead)) * z
		var dist := muzzle.distance_to(target)
		var end := muzzle.lerp(target, minf(1.0, reach_px / maxf(dist, 1.0)))
		_dashed_line(muzzle, end, Color(ACCENT, 0.4), 1.5)
		drawn_aim_line = true

	# what the pointer is over (a container in reach says so in its prompt; this is the pointer's own tag for one out of reach)
	var hv = scene.hover
	if hv != null and hv.kind == "container" and scene.reach_container.is_empty():
		var c2: Dictionary = hv.ref
		var at3: Vector2 = scene.to_screen(Vector2(c2.at))
		_tag(at3 + Vector2(0.0, -0.7 * z - 8.0), "%s: %d s to search" % [String(c2.kind).capitalize(), int(ceilf(float(c2.search_s)))], font, INK)

	# the crosshair: four arms and a ring that is the cone of the next shot, at the pointer (the system's arrow is hidden over the world)
	if scene.crosshair_shown():
		var m2: Vector2 = scene._mouse
		var bloom: float = float(lead.bloom) if lead != null else 0.0
		var ring := RING_MIN + minf(bloom, 2.0) * 10.0 + (3.0 if lead != null and lead.moving else 0.0)
		var cc := Color(ACCENT, 0.95)
		draw_arc(m2, ring, 0, TAU, 28, Color(0, 0, 0, 0.45), 3.0, true)
		draw_arc(m2, ring, 0, TAU, 28, cc, 1.5, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(m2 + d * (ring + CROSS_GAP - 4.0), m2 + d * (ring + CROSS_GAP + CROSS_ARM), Color(0, 0, 0, 0.45), 3.0, true)
			draw_line(m2 + d * (ring + CROSS_GAP - 4.0), m2 + d * (ring + CROSS_GAP + CROSS_ARM), cc, 1.5, true)
		draw_circle(m2, 1.6, cc)
		drawn_crosshair = true
