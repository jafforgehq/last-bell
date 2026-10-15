## EXPERIMENT (prison UI round 2): the readable world. One Control on the HUD layer (screen space, so text stays one size at every zoom) draws
## - a role-coloured ring under every crew member's feet (roles read from a distance),
## - over each head a small job icon and a one-word state ("Gate", "Farming", "Nursing"...), with the full name and job when Ruth is within 6 tiles or the pointer is on them; the word hides at distance,
## - small name plates on the buildings (INFIRMARY, CANTEEN, WORKSHOP, STORES, DORMITORY, GATE...) that show when Ruth is near (all of them in the overview),
## - the guidance marker: a pulsing ring and a bouncing arrow at the place of the first open objective (prison_topbar.gd `focus()`), an edge arrow when it is off screen.
## The job of a person is read from what the crew module says it is doing (`m.say`, `m.state`), role colours from the economy's role table (so changing a role in the roster recolours the ring).
extends RefCounted

const Icons := preload("res://scripts/prison/prison_icons.gd")
const Base := preload("res://scripts/prison/prison_base.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const ROLE_COL := {
	"gardener": Color("#8fd05a"), "cook": Color("#f0a040"), "medic": Color("#f27f9a"), "mechanic": Color("#6fb4e8"),
	"guard": Color("#f0d24a"), "cleaner": Color("#5fd0c0"), "hauler": Color("#c9a070"), "kid": Color("#e8a8d0"), "ally": Color("#a8d8ff"),
}
const ROLE_NAME := {"gardener": "Gardener", "cook": "Cook", "medic": "Medic", "mechanic": "Mechanic", "guard": "Guard", "cleaner": "Cleaner", "hauler": "Hauler", "kid": "Child", "ally": "Survivor"}
## First match wins: [words in what the crew says, icon, one-word state].
const JOBS := [
	["down", "cross", "Down"], ["contact", "bell", "Alert"], ["here they come", "bell", "Alert"], ["firing", "target", "Firing"],
	["gate", "binoculars", "Gate"], ["patrol", "boot", "Patrol"], ["watch", "binoculars", "Watch"],
	["hoeing", "leaf", "Farming"], ["planting", "leaf", "Farming"], ["cooking", "pot", "Cooking"], ["serving", "pot", "Cooking"],
	["tending", "cross", "Nursing"], ["mixing", "cross", "Nursing"], ["loading rounds", "ammo", "Ammo"],
	["mending", "wrench", "Repair"], ["vise", "wrench", "Repair"], ["building", "hammer", "Building"],
	["sweeping", "broom", "Cleaning"], ["wiping", "broom", "Cleaning"], ["washing", "broom", "Cleaning"], ["rubbish", "broom", "Cleaning"],
	["eating", "fork", "Eating"], ["chatting", "rest", "Resting"], ["waiting for a job", "rest", "Resting"], ["waiting for scrap", "clock", "Waiting"],
	["water", "water", "Water"], ["crates", "crate", "Hauling"], ["counting", "crate", "Stores"],
	["tag", "play", "Playing"], ["gotcha", "play", "Playing"], ["running", "play", "Playing"], ["shaken", "play", "Playing"],
	["ready", "boot", "Follow"], ["following", "boot", "Follow"], ["hanging", "boot", "Follow"], ["back up", "boot", "Follow"],
]
const ROLE_JOB := {"gardener": ["leaf", "Farming"], "cook": ["pot", "Cooking"], "medic": ["cross", "Nursing"], "mechanic": ["wrench", "Repair"], "guard": ["shield", "Guard"], "cleaner": ["broom", "Cleaning"], "hauler": ["crate", "Hauling"]}
const PLATE_NAME := {"CELL BLOCK": "DORMITORY"}
const NEAR_TAG := 6.0
const MID_TAG := 13.0
const NEAR_PLATE := 15.0

var game
var c: Control
var hover_id := ""
var leaver_id := ""    # who would quit first, while morale is within 10 of the limit
var near_id := ""    # the one nearest person within 6 tiles gets the full name line (a clump does not stack its names)
var _font: Font
var _plate_box: StyleBoxFlat


func _init(g) -> void:
	game = g
	c = Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(_draw)
	g.hud.add_child(c)
	g.hud.move_child(c, 0)
	_font = Fonts.sans(700)
	_plate_box = StyleBoxFlat.new()
	_plate_box.bg_color = Color(0.03, 0.05, 0.04, 0.78)
	_plate_box.set_corner_radius_all(4)
	_plate_box.set_content_margin_all(0)


func frame() -> void:
	c.queue_redraw()


## [icon, word] of what a person is doing, by their own words.
func job_of(m: Dictionary) -> Array:
	var st := String(m.state)
	if st == "downed" or st == "down":
		return ["cross", "Down"]
	if st == "leaving":
		return ["exit", "Leaving"]
	var say := String(m.get("say", "")).to_lower()
	if say == "firing" and float(game.aim_hold.get(m.p.id, 0.0)) <= 0.0:
		say = ""    # (the word stays after the shot; the pose has gone back to the watch)
	for j in JOBS:
		if say.contains(String(j[0])):
			return [j[1], j[2]]
	if st == "post":
		return ["shield", "Guard"]
	var role := role_of(m)
	if ROLE_JOB.has(role):
		return ROLE_JOB[role]
	return ["rest", "Idle"]


func role_of(m: Dictionary) -> String:
	if m.def.has("ally"):
		return "ally"
	if m.def.has("play"):
		return "kid"
	var r := String(game.econ.cfg.crew_role.get(String(m.def.id), "")) if game.econ != null else ""
	if r != "":
		return r
	return "guard" if m.def.has("stand") else "hauler"


func _to_scr(p: Vector2, v: Vector2) -> Vector2:
	return (p - game.cam_center) * game.zoom_px + v / 2.0


func _text_plate(at: Vector2, text: String, size: int, col: Color, left_pad := 0.0) -> float:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_style_box(_plate_box, Rect2(at + Vector2(-4.0, -float(size) + 1.0), Vector2(w + 8.0 + left_pad, float(size) + 5.0)))
	c.draw_string(_font, at + Vector2(left_pad, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


func _draw() -> void:
	if game.run == null or game.busy or game.crew == null:
		return
	var v: Vector2 = game._vp()
	var zoom: float = game.zoom_px
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var mouse: Vector2 = game.get_viewport().get_mouse_position()
	if game.args.has("tagat"):    # a check: pretend the pointer is on this person
		var tm = game.crew.member_of(String(game.args.tagat))
		if not tm.is_empty():
			mouse = _to_scr(Vector2(tm.p.x, tm.p.y - 0.8), v)
	var is_base: bool = game.mode == "base"
	if is_base:
		_plates(me, v, zoom)
	hover_id = ""
	near_id = ""
	leaver_id = ""
	var ec = game.econ
	if is_base and game.phase == "managed" and ec != null and ec.morale < float(ec.cfg.morale.leave_below) + 10.0 and ec.people() > int(ec.cfg.morale.keep_min):
		var lv = ec.next_leaver()
		if lv != null:
			leaver_id = String(lv.id)
	var nd := NEAR_TAG
	for m in game.crew.members:
		var dd := me.distance_to(Vector2(m.p.x, m.p.y))
		if dd < nd and is_base:
			nd = dd
			near_id = String(m.def.id)
	var best := 28.0
	if is_base:
		for m in game.crew.members:
			var d := _to_scr(Vector2(m.p.x, m.p.y - 0.8), v).distance_to(mouse)
			if d < best:
				best = d
				hover_id = String(m.def.id)
		for m in game.crew.members:
			_member(m, me, v, zoom)
		_guide(me, v, zoom)


func _plates(me: Vector2, v: Vector2, zoom: float) -> void:
	for l in game.base.labels:
		var lp := Vector2(l.pos)
		var d := me.distance_to(lp)
		var a := 1.0 if game.map_view else clampf((NEAR_PLATE - d) / 4.0, 0.0, 1.0)
		if a <= 0.01:
			continue
		var sp := _to_scr(lp, v)
		if not Rect2(Vector2(-60, -20), v + Vector2(120, 40)).has_point(sp):
			continue
		var text := String(PLATE_NAME.get(String(l.text), String(l.text)))
		var size := 12 if zoom >= 20.0 else 10
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var col := Color(1.0, 0.95, 0.75, a)
		_plate_box.bg_color = Color(0.03, 0.05, 0.04, 0.78 * a)
		_text_plate(sp - Vector2(w / 2.0, 0), text, size, col)
	_plate_box.bg_color = Color(0.03, 0.05, 0.04, 0.78)


func _member(m: Dictionary, me: Vector2, v: Vector2, zoom: float) -> void:
	var p: Vector2 = Vector2(m.p.x, m.p.y)
	var feet := _to_scr(p, v)
	if not Rect2(Vector2(-50, -60), v + Vector2(100, 120)).has_point(feet):
		return
	if m.has("node") and is_instance_valid(m.node) and not (m.node as Node2D).visible:
		return
	var role := role_of(m)
	var col: Color = ROLE_COL.get(role, Color.WHITE)
	var d := me.distance_to(p)
	var hov: bool = hover_id == String(m.def.id)
	# the ring under the feet
	var sc := float(m.def.get("scale", 1.0))
	var rr := maxf(5.0, 0.42 * zoom * sc)
	c.draw_set_transform(feet + Vector2(0, 0.05 * zoom), 0.0, Vector2(1.0, 0.45))
	c.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(0.02, 0.03, 0.03, 0.55), 4.0, true)
	c.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(col, 0.95 if (hov or d < MID_TAG) else 0.75), 2.2 if hov else 1.6, true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if zoom < 12.0:    # the overview: a dot is all there is room for
		c.draw_circle(feet - Vector2(0, 7), 3.0, col)
		return
	var near := near_id == String(m.def.id) or hov
	if m.def.has("ally") and not near and zoom >= 12.0:    # a friend always shows a coloured name and a health bar over the head
		var ac := Color(String(m.def.look.get("top", "#a8d8ff"))).lightened(0.55)
		var an := String(m.def.name)
		var aw := _font.get_string_size(an, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var atop := _to_scr(Vector2(p.x, p.y - 1.55 * sc), v) + Vector2(0, -18)
		_text_plate(atop + Vector2(-aw / 2.0, 0), an, 12, Color("#ff8a7a") if String(m.state) == "downed" else ac)
	var mid := d < MID_TAG or near
	var job := job_of(m)
	var top := _to_scr(Vector2(p.x, p.y - 1.55 * sc), v)
	var downed: bool = String(m.state) == "downed" or String(m.state) == "down"
	var icol: Color = Color("#ff8a7a") if downed else col
	var cc := top + Vector2(0, -2)
	c.draw_circle(cc, 10.5, Color(0.03, 0.05, 0.04, 0.82))
	c.draw_arc(cc, 10.5, 0.0, TAU, 20, icol, 2.0, true)
	Icons.draw(c, String(job[0]), cc, 14.0, icol.lightened(0.15))
	if leaver_id == String(m.def.id):    # a small amber badge: this one is close to leaving (low morale)
		var bc := cc + Vector2(-20, -2)
		c.draw_circle(bc, 8.5, Color(0.03, 0.05, 0.04, 0.88))
		c.draw_arc(bc, 8.5, 0.0, TAU, 16, Hud.WARN, 2.0, true)
		Icons.draw(c, "exit", bc, 11.0, Hud.WARN)
	var y_line := cc.y - 16.0
	if mid:
		var word := String(job[1])
		_text_plate(Vector2(cc.x + 14.0, cc.y + 4.0), word, 12, Color(icol.lightened(0.3), 1.0))
	if near:
		var nm := "%s - %s" % [String(m.def.name), String(m.def.role) if String(m.def.get("role", "")) != "" else ROLE_NAME.get(role, "")]
		var sub := String(m.get("say", ""))
		var text := nm
		if sub != "" and sub != String(m.def.role):
			text = "%s: %s" % [nm, sub]
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text_plate(Vector2(cc.x - tw / 2.0, y_line), text, 13, Color(1, 1, 1, 0.97))
		y_line -= 18.0
	# the work bar and an ally's health
	var bar := cc + Vector2(-16, 14)
	if m.def.has("ally"):
		var f2 := clampf(float(m.hp) / 45.0, 0.0, 1.0)
		c.draw_rect(Rect2(bar + Vector2(0, 14), Vector2(32, 4)), Color(0, 0, 0, 0.7))
		c.draw_rect(Rect2(bar + Vector2(0, 14), Vector2(32.0 * f2, 4)), Color(0.3, 0.85, 0.35) if f2 > 0.3 else Color(0.9, 0.25, 0.2))
	if String(m.state) == "work" and mid and not m.def.has("ally"):
		var stop: Dictionary = m.eat if m.has("eat") else m.def.route[m.i]
		var f := clampf(float(m.t) / maxf(0.1, float(stop.secs)), 0.0, 1.0)
		c.draw_rect(Rect2(bar + Vector2(0, 14), Vector2(32, 4)), Color(0, 0, 0, 0.65))
		c.draw_rect(Rect2(bar + Vector2(0, 14), Vector2(32.0 * f, 4)), Color(0.95, 0.8, 0.3))


func _guide(me: Vector2, v: Vector2, zoom: float) -> void:
	if game.board.is_open() or game.pack.ui.is_open():
		return
	var f: Dictionary = game.topbar.focus()
	if f.is_empty():
		return
	var tp: Vector2 = f.pos
	if me.distance_to(tp) < 3.5:
		return
	var sp := _to_scr(tp, v)
	var pulse := 0.5 + 0.5 * sin(game.clock * 4.0)
	var gold := Color(0.99, 0.82, 0.3)
	var margin := Rect2(Vector2(28, 90), (v - Vector2(56, 130)).max(Vector2.ONE))
	if margin.has_point(sp):
		var r := maxf(18.0, 1.1 * zoom) * (0.92 + 0.12 * pulse)
		c.draw_set_transform(sp, 0.0, Vector2(1.0, 0.55))
		c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 5.0, true)
		c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(gold, 0.55 + 0.4 * pulse), 3.0, true)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var by := sp.y - r * 0.55 - 30.0 - 6.0 * pulse
		c.draw_colored_polygon(PackedVector2Array([Vector2(sp.x, by + 16), Vector2(sp.x - 11, by), Vector2(sp.x + 11, by)]), Color(0, 0, 0, 0.6))
		c.draw_colored_polygon(PackedVector2Array([Vector2(sp.x, by + 13), Vector2(sp.x - 8, by + 2), Vector2(sp.x + 8, by + 2)]), gold)
		var text := String(f.label)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text_plate(Vector2(sp.x - tw / 2.0, by - 6.0), text, 13, gold)
	else:
		var dir := (sp - v / 2.0).normalized()
		var edge := v / 2.0 + dir * minf((v.x / 2.0 - 46.0) / maxf(absf(dir.x), 0.001), (v.y / 2.0 - 70.0) / maxf(absf(dir.y), 0.001))
		c.draw_colored_polygon(PackedVector2Array([edge + dir * 16, edge + dir.rotated(2.45) * 14, edge + dir.rotated(-2.45) * 14]), Color(0, 0, 0, 0.6))
		c.draw_colored_polygon(PackedVector2Array([edge + dir * 13, edge + dir.rotated(2.45) * 10, edge + dir.rotated(-2.45) * 10]), Color(gold, 0.6 + 0.4 * pulse))
		var text2 := "%s  %d" % [String(f.label), int(me.distance_to(tp))]
		var tw2 := _font.get_string_size(text2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text_plate(edge - dir * 28.0 - Vector2(tw2 / 2.0, -4.0), text2, 12, gold)
