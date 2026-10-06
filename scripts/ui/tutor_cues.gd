## TEACH BY DOING (One House, TUTOR): the lessons of the first house are taught by a cue IN THE WORLD, at the thing to do, and the lesson card is only a small chip ("STEP 2 OF 8", and the
## verb: "Shoot it"). A VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_event(e)`). It reads the guide (`sim.scenario.guide()`: the
## lesson of now) and the rules' state and writes nothing in them; the scripted first minute it draws the ammo box of is scripts/town/opening.gd's.
##
##   lesson            the cue (drawn on the HUD's own layer, under its panels, so its type is one size at any zoom)
##   walk              the keys W A S D beside her, each lit while it is pressed, until she has walked six tiles (the painted chevrons on the road are the town's own)
##   shoot             a ring on the nearest of the dead awake (on the walker: it is the one coming), bold with ticks once it is in reach of the gun; and beside her the mouse: "Hold the
##                     right button to aim, click to fire" (the mouse aims by itself under "Always aim at the mouse": its words say so) until the first shot is fired; a chevron at the window's
##                     edge when the dead one is off the screen
##   reload            "Reload: R" beside her with the magazine's rounds as pips, while the gun is low and not being reloaded
##   find              a ring on the front door of the nearest house that can be claimed
##   door              an outline round the door: the nearest one of the house she is in with a room behind it she has not seen (the front door of the nearest house from outside)
##   clear             none (the room-clear chip of scripts/ui/room_flash.gd is the cue)
##   search            a "?" badge over the first container nobody has searched in the room she is in (the nearest of the house when there is none in this room)
##   claim             a ring at the spot where E claims
##   ask               a ring round the first card of the crew at the top of the window
## EARLY (five lessons): the cues are the lesson's `phase`: shoot is the shot and then the reload ("Reload: R"); claim is the ring on the front door on the road in (phase find), nothing in the house (the room chip is the
## cue), the ring where E claims (phase claim); build is the outline on the way to the Build page (the radio's button, the Build tab, the NEXT card's button) and then the ring on the section waiting for her hands ("Hold E
## here"); door, clear and search are HINTS (the card says HINT), each the old cue with one line on the thing.
## Each cue is gone the moment its lesson is done, with a small confirm sound (`ui_confirm`); the next begins after a short beat (BEAT_S). A lesson skipped, or "No lessons" (the flag of the
## town HUD's card, and the Esc menu's Lessons), puts its cue away too. The ammo box of the opening is drawn whatever the lessons say: it is in the world.
## THE REFUSAL MARKER (not a lesson): while a claim is refused because a room has not been looked into (the words "You have not looked in the utility yet"), a ring on that room's doorway.
## THE REHEARSAL CARD: at the first claim, after the banner, "The dead come at the bell. Fortify before dark: N opens the Build page." with Show me (opens the page); in the left column under the
## objective, for `rehearsal.show_s` seconds.
## REDUCE MOTION and REDUCE FLASHES (`Access.calm_flashes()`): no pulse, no halo: a still outline. COLOUR-BLIND markers: every cue is a shape (a ring, an outline, a badge, a key), never a colour alone.
## STAGING: `--lesson=<walk|shoot|reload|find|door|door:in|clear|search|claim|ask|refusal|rehearsal>` puts the run where that lesson is the one of now and stops the clock (see README);
## `--lesson-cost` prints the CPU time of this part per frame.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const TownHud := preload("res://scripts/ui/town_hud.gd")
const BuildStage := preload("res://scripts/ui/build_stage.gd")

const GOLD := Color(0.941, 0.761, 0.29)
const DARK := Color(0.04, 0.08, 0.07)
const INK := Color(0.93, 0.96, 0.89)
const INK2 := Color(0.78, 0.82, 0.74)
const BRASS := Color(0.86, 0.68, 0.26)
const CRATE_PATH := "res://assets/objects/tool_crate.png"
## The pause between one lesson's cue going and the next one's beginning, and how long a cue takes to come up.
const BEAT_S := 0.45
const FADE_S := 0.3
const PULSE_HZ := 1.5
## How near (tiles) the ammo box shows its ring and label; how far the dead one's ring looks for it.
const BOX_NEAR := 10.0
const TARGET_R := 20.0
const KEY_PX := 28.0
const PAD := 8.0
const REFUSAL_S := 8.0
const POP_S := 1.6
const REACH_FALLBACK := 7.5

var main
var hud
var sim
var layer: Control
## EARLY: a layer over the HUD's boards for the one cue that points at a control of the HUD (the Build button), and what it draws.
var top: Control
var _top_rect := Rect2()
var _top_a := 1.0
## The lesson whose cue is up ("" none), seconds since it came up, and the pause still to go before it does.
var cue := ""
## EARLY: what the lesson is about now (the guide's `phase`) and the one line of a hint's cue.
var cue_phase := ""
var _hint_line := ""
var cue_age := 0.0
var beat := 0.0
## The rehearsal card (made once) and how long it has left.
var card: PanelContainer
var card_label: Label
var card_left := 0.0
var card_armed := -1.0
var rehearsed := false
## What was drawn at the last frame (the screenshots' log reads them).
var drawn := ""

var _now := 0.0
var _calm := false
var _confirmed := {}
var _shots0 := -1
var _refusal_until := -1.0
var _crate: Texture2D
var _pops: Array = []
var _spec := ""
var _staged := false
var _freeze := true
var _cost := false
var _cost_us := 0.0
var _cost_n := 0
var _cost_done := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	sim = main.get("sim")
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--lesson="):
			_spec = a.trim_prefix("--lesson=")
		elif a == "--lesson-cost":
			_cost = true
	if hud == null:
		return
	layer = Control.new()
	layer.name = "TutorCues"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(_draw_layer)
	hud.add_child(layer)
	# (under the HUD's own boards, as the candidates' marks and the objective's arrow are: a cue in the world is never over a panel)
	hud.move_child(layer, 0)
	top = Control.new()
	top.name = "TutorCuesTop"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top.draw.connect(_draw_top)
	hud.add_child(top)
	if ResourceLoader.exists(CRATE_PATH):
		_crate = load(CRATE_PATH)
	_build_card()


func _scenario():
	return sim.get("scenario") if sim != null else null


func _me():
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


func _opening():
	var sc = _scenario()
	var op = sc.get("opening") if sc != null else null
	return op if op != null and bool(op.built) else null


func _hud_part():
	var town = main.get("town")
	return town.part("town_hud") if town != null and town.has_method("part") else null


# ------------------------------------------------------------------------------ frames --

func on_frame(dt: float) -> void:
	if layer == null or sim == null:
		return
	var t0 := Time.get_ticks_usec() if _cost else 0
	_now += dt
	_calm = Access.calm_flashes()
	_stage()
	BuildStage.on_frame(main)    # (a screenshot's `--build=...`: the front fence ordered and her hands at it; nothing without the flag)
	if _staged and _freeze:
		main.speed = 0    # (a staged picture stays where it was staged)
	_read_lesson(dt)
	_step_pops(dt)
	_step_card(dt)
	layer.queue_redraw()
	if top != null:
		top.queue_redraw()
	if _cost:
		_cost_us += float(Time.get_ticks_usec() - t0)
		_cost_n += 1
		if not _cost_done and _cost_n >= 50:
			_cost_done = true
			print("tutor cues: %.1f us a frame (%d frames), cue '%s'" % [_cost_us / float(_cost_n), _cost_n, cue])


## The lesson of now (the guide's), its cue, the confirm sound when it is done and the beat before the next.
func _read_lesson(dt: float) -> void:
	var sc = _scenario()
	var g: Dictionary = sc.guide() if sc != null and sc.has_method("guide") else {}
	var id := String(g.get("id", ""))
	var th = _hud_part()
	var off: bool = (th != null and (not bool(th.lessons_are_on()) or (th.get("skipped") is Dictionary and (th.skipped as Dictionary).has(id))))
	if g.is_empty() or id == "":
		cue = ""
		return
	if bool(g.get("done", false)):
		cue = ""
		if not _confirmed.has(id):
			_confirmed[id] = true
			beat = BEAT_S
			if not off:
				_confirm_sound()
		return
	_confirmed.erase(id)
	if off:
		cue = ""
		return
	# (EARLY: a lesson has phases, and the card may be a hint: the cue follows what the player is at, and comes up afresh when that changes)
	var phase := String(g.get("phase", ""))
	_hint_line = String(g.get("line", ""))
	if id != cue:
		cue = id
		cue_phase = phase
		cue_age = 0.0
		var me = _me()
		_shots0 = int(me.stats.shots) if me != null else 0
	elif phase != cue_phase:
		cue_phase = phase
		cue_age = 0.0
	if beat > 0.0:
		beat -= dt
	else:
		cue_age += dt


func _confirm_sound() -> void:
	var sound = main.get("sound")
	if sound != null and sound.has_method("ui"):
		sound.ui("ui_confirm", 0.55, 0.0)


func on_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"supply_taken":
			var loot = e.get("loot", {})
			var words := TownHud.loot_text(loot) if loot is Dictionary else ""
			_pops.append({"text": ("+" + words) if words != "" else "Taken", "at": e.get("at", Vector2.ZERO), "age": 0.0})
		"claimed":
			_arm_card()
		"interact":
			if String(e.get("kind", "")) == "claim" and not bool(e.get("ok", true)):
				_refusal_until = _now + REFUSAL_S


func _step_pops(dt: float) -> void:
	var i := _pops.size() - 1
	while i >= 0:
		_pops[i].age = float(_pops[i].age) + dt
		if float(_pops[i].age) >= POP_S:
			_pops.remove_at(i)
		i -= 1


# ---------------------------------------------------------------------------- the staging --

func _stage() -> void:
	if _spec == "" or _staged or Engine.get_frames_drawn() < 6:
		return
	_staged = true
	var sc = _scenario()
	# (`--lesson=shoot:run`: the lesson as `shoot:out` and then the clock goes on: the walker comes at her while the frames pass, `--speed=` quickens it)
	if _spec.ends_with(":run"):
		_spec = _spec.trim_suffix(":run") + ":out"
		_freeze = false
	var take := _spec.ends_with(":take")    # (`--lesson=reload:take`: the shells taken at once: the pop "+8 ammo" over the empty place)
	if take:
		_spec = _spec.trim_suffix(":take")
	if _spec == "rehearsal":
		_show_card()
	elif sc == null or not sc.has_method("stage_lesson") or not bool(sc.stage_lesson(_spec)):
		print("--lesson=%s: no such lesson, or not a town run (give --town)" % _spec)
		return
	if take and _opening() != null:
		var op = _opening()
		var at: Vector2 = op.box_at
		op._taken()
		on_event({"type": "supply_taken", "loot": op.box_loot, "at": at})
	var me = _me()
	if me != null:
		var look := Vector2(me.x, me.y)
		var op = _opening()
		if _spec.begins_with("shoot") and op != null and op.zombie != null:
			look = (look + Vector2(op.zombie.x, op.zombie.y)) * 0.5
		main.cam_center = look
		main.cam_hold = 0.0
	if _freeze:
		main.speed = 0


# --------------------------------------------------------------------------------- screen --

func _view() -> Vector2:
	return layer.size if layer != null and layer.size.x > 1.0 else Vector2(1280, 800)


## World tile -> HUD pixel (the camera is main's: centre tile and pixels per tile).
func _s(tile: Vector2) -> Vector2:
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	return (tile - cam) * _zoom() + _view() * 0.5


func _zoom() -> float:
	return float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0


func _body() -> Vector2:
	var me = _me()
	if me == null:
		return Vector2(-100, -100)
	var at := Vector2(me.x, me.y)
	if main.has_method("view_pos"):
		at = main.view_pos(me)
	return _s(at) + Vector2(0, -0.45 * _zoom())


func _pulse() -> float:
	return 1.0 if _calm else 0.5 + 0.5 * sin(_now * TAU * PULSE_HZ)


func _fade() -> float:
	return 1.0 if _calm else clampf(cue_age / FADE_S, 0.0, 1.0)


func _sleeping() -> bool:
	var sl = sim.get("sleep")
	return sl != null and sl.has_method("active") and bool(sl.active())


func _px(n: int) -> int:
	return Access.scaled(n)


# ------------------------------------------------------------------------------- drawing --

func _draw_layer() -> void:
	drawn = ""
	_top_rect = Rect2()
	if hud == null or sim == null or _me() == null:
		return
	_draw_box()
	_draw_pops()
	if _sleeping():
		return
	if beat <= 0.0 and cue != "":
		match cue:
			"walk":
				_cue_walk()
			"shoot":
				# (the one lesson of the gun: the shot, then the reload)
				if cue_phase == "reload":
					_cue_reload()
				else:
					_cue_shoot()
			"claim":
				# (the claim lesson: the front door on the road in, nothing in the house itself (the room chip is the cue), the spot where E claims once it is clear)
				if cue_phase == "find":
					_cue_find()
				elif cue_phase == "claim":
					_cue_claim()
			"build":
				_cue_build()
			"door", "clear", "search":
				_cue_hint()
			"ask":
				_cue_ask()
	_draw_refusal()


## A pulsing ring: a dark rim, the gold line, and (unless the settings say still) a halo that goes out from it and fades. `bold` adds ticks at the four sides (a shape that says "now").
func _ring(c: Vector2, r: float, a: float = 1.0, bold: bool = false) -> void:
	var w := 4.0 if bold else 3.0
	layer.draw_arc(c, r, 0.0, TAU, 48, Color(DARK, 0.85 * a), w + 3.0, true)
	layer.draw_arc(c, r, 0.0, TAU, 48, Color(GOLD, a), w, true)
	if not _calm:
		var k := fposmod(_now * 0.9, 1.0)
		layer.draw_arc(c, r + 4.0 + 14.0 * k, 0.0, TAU, 48, Color(GOLD, 0.55 * (1.0 - k) * a), 2.5, true)
	else:
		layer.draw_arc(c, r + 5.0, 0.0, TAU, 48, Color(GOLD, 0.35 * a), 2.0, true)
	if bold:
		for q in 4:
			var d := Vector2.from_angle(float(q) * PI * 0.5)
			layer.draw_line(c + d * (r - 7.0), c + d * (r + 7.0), Color(GOLD, a), 3.0)


## A pulsing outline of a rectangle (pixels).
func _outline(rc: Rect2, a: float = 1.0, ci: CanvasItem = null) -> void:
	var c: CanvasItem = ci if ci != null else layer
	var p := _pulse()
	var grow := 3.0 + (3.0 * p if not _calm else 2.0)
	var r2 := rc.grow(grow)
	c.draw_rect(r2, Color(GOLD, 0.10 * a), true)
	c.draw_rect(r2.grow(1.5), Color(DARK, 0.8 * a), false, 5.0)
	c.draw_rect(r2, Color(GOLD, (0.65 + 0.35 * p) * a), false, 3.0)


## EARLY: what is drawn over the HUD's own boards (the toolbar's button, the radio's tab: a control of the HUD cannot be pointed at from under it).
func _draw_top() -> void:
	if _top_rect.has_area() and cue == "build" and beat <= 0.0:
		_outline(_top_rect, _top_a, top)


## A key cap with its letter, lit when `lit`.
func _key(rc: Rect2, text: String, lit: bool, a: float = 1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GOLD, 0.95 * a) if lit else Color(0.93, 0.96, 0.89, 0.16 * a)
	sb.border_color = Color(GOLD, a) if lit else Color(INK, 0.55 * a)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.anti_aliasing = true
	layer.draw_style_box(sb, rc)
	var f := Fonts.cond(700)
	var size := _px(17)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	layer.draw_string(f, rc.position + Vector2((rc.size.x - w) * 0.5, rc.size.y * 0.5 + float(size) * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(DARK, a) if lit else Color(INK, a))


## A dark plate with a gold edge, the HUD's own look.
func _plate(rc: Rect2, a: float = 1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DARK, 0.88 * a)
	sb.border_color = Color(GOLD, 0.8 * a)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.anti_aliasing = true
	layer.draw_style_box(sb, rc)


## Where a plate of `size` stands beside the avatar: up and to the side with more room (above the E prompt's pill, which stands at her body's height), the first place that is inside the
## window and clear of the HUD's boards (its columns, the crew's cards, the clock, the toolbar), else the first that is inside the window.
func _beside(body: Vector2, size: Vector2) -> Vector2:
	var vp := _view()
	var right := body.x < vp.x * 0.5
	var up := body.y - 78.0 - size.y
	var spots: Array = [
		Vector2(body.x + 36.0 if right else body.x - 36.0 - size.x, up),
		Vector2(body.x - 36.0 - size.x if right else body.x + 36.0, up),
		Vector2(body.x + 70.0 if right else body.x - 70.0 - size.x, body.y - size.y * 0.5 - 20.0),
		Vector2(body.x - 70.0 - size.x if right else body.x + 70.0, body.y - size.y * 0.5 - 20.0),
		Vector2(body.x - 120.0 - size.x if not right else body.x + 120.0, up),
		Vector2(body.x - size.x * 0.5, up - 10.0),
		Vector2(body.x + 36.0 if right else body.x - 36.0 - size.x, body.y + 46.0),
	]
	var inside := Rect2(Vector2(PAD, 70.0), vp - Vector2(PAD * 2.0, 70.0 + 90.0))
	var first := Vector2.INF
	var blocks := _hud_rects()
	for s in spots:
		var rc := Rect2(s, size)
		if not inside.encloses(rc):
			continue
		if first == Vector2.INF:
			first = s
		var clear := true
		for b in blocks:
			if rc.intersects(b):
				clear = false
				break
		if clear:
			return s
	if first != Vector2.INF:
		return first
	return Vector2(clampf(spots[0].x, PAD, maxf(vp.x - size.x - PAD, PAD)), clampf(spots[0].y, 70.0, maxf(vp.y - size.y - 90.0, 70.0)))


## The boards of the HUD that a plate must not stand under (screen rectangles, a little grown).
func _hud_rects() -> Array:
	var out: Array = []
	var origin := layer.get_global_rect().position
	for name in ["left_col", "right_col", "bar", "speed_panel", "dock", "inspect", "radio_box", "help", "radio_panel", "banner"]:
		var c = hud.get(name)
		if c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree() and (c as Control).modulate.a > 0.05:
			out.append(Rect2((c as Control).get_global_rect().position - origin, (c as Control).size).grow(6.0))
	# the objective's arrow round her feet, and its distance in tiles
	var th = _hud_part()
	if th != null and bool(th.get("_arrow_on")):
		var dir := Vector2.from_angle(float(th.bearing))
		var c2 := _body() + dir * (maxf(58.0, 1.7 * _zoom()) + 20.0)
		out.append(Rect2(c2 - Vector2(40.0, 20.0), Vector2(80.0, 40.0)))
	return out


func _text(pos: Vector2, text: String, size: int, col: Color, bold: bool = true) -> float:
	var f := Fonts.cond(700) if bold else Fonts.sans(400)
	layer.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _edge_chevron(target: Vector2, a: float) -> void:
	var vp := _view()
	var c := vp * 0.5
	var d := target - c
	if d.length() < 1.0:
		return
	var k := minf((vp.x * 0.5 - 40.0) / maxf(absf(d.x), 0.001), (vp.y * 0.5 - 70.0) / maxf(absf(d.y), 0.001))
	var at := c + d * minf(k, 1.0)
	TownHud._draw_chevron(layer, at, d.angle(), 13.0, Color(GOLD, a), Color(DARK, 0.9 * a))


# ------------------------------------------------------------------------------- the cues --

func _cue_walk() -> void:
	var a := _fade()
	var sz := Vector2(KEY_PX * 3.0 + 4.0 * 2.0 + 20.0, KEY_PX * 2.0 + 4.0 + 20.0 + float(_px(15)) + 6.0)
	var at := _beside(_body(), sz)
	_plate(Rect2(at, sz), a)
	var o := at + Vector2(10.0, 10.0)
	var caps := {"W": [Vector2(1, 0), [KEY_W, KEY_UP]], "A": [Vector2(0, 1), [KEY_A, KEY_LEFT]], "S": [Vector2(1, 1), [KEY_S, KEY_DOWN]], "D": [Vector2(2, 1), [KEY_D, KEY_RIGHT]]}
	for k in caps:
		var cell: Vector2 = caps[k][0]
		var lit := false
		for code in caps[k][1]:
			lit = lit or Input.is_key_pressed(code)
		_key(Rect2(o + Vector2(cell.x * (KEY_PX + 4.0), cell.y * (KEY_PX + 4.0)), Vector2(KEY_PX, KEY_PX)), String(k), lit, a)
	_text(o + Vector2(0.0, KEY_PX * 2.0 + 4.0 + float(_px(15)) + 2.0), "Walk", _px(15), Color(INK, a))
	drawn = "walk"


func _cue_shoot() -> void:
	var a := _fade()
	var sc = _scenario()
	var me = _me()
	var target: Dictionary = sc.nearest_dead(TARGET_R + 6.0) if sc != null and sc.has_method("nearest_dead") else {}
	var op = _opening()
	if op != null and op.walker_alive():
		target = {"x": float(op.zombie.x), "y": float(op.zombie.y), "dist": Vector2(me.x - op.zombie.x, me.y - op.zombie.y).length()}
	var body := _body()
	if not target.is_empty():
		var z := _zoom()
		var c := _s(Vector2(float(target.x), float(target.y))) + Vector2(0, -0.4 * z)
		var reach := float(sim.gun_of(me).get("range", REACH_FALLBACK)) if sim.has_method("gun_of") else REACH_FALLBACK
		var inside := float(target.dist) <= reach
		var vp := Rect2(Vector2.ZERO, _view()).grow(-24.0)
		if vp.has_point(c):
			_ring(c, maxf(0.75 * z, 20.0), a, inside)
		else:
			_edge_chevron(c, a)
	if int(me.stats.shots) <= _shots0:
		var always := AimMode.always()
		var line := "Move the mouse to aim, click to fire" if always else "Hold the right button to aim, click to fire"
		var f := Fonts.cond(700)
		var size := _px(16)
		var w := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var box := Vector2(w + 62.0, 44.0)
		var at := _beside(body, box)
		_plate(Rect2(at, box), a)
		_mouse(at + Vector2(14.0, 8.0), a, not always)
		_text(at + Vector2(50.0, 28.0), line, size, Color(INK, a))
	drawn = "shoot"


## The mouse: a body, the two buttons, and the button to press (the right, or the left to fire) filled in gold and pulsing.
func _mouse(at: Vector2, a: float, right_button: bool) -> void:
	var body := Rect2(at, Vector2(22.0, 30.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.96, 0.89, 0.14 * a)
	sb.border_color = Color(INK, 0.8 * a)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 11
	sb.corner_radius_top_right = 11
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.anti_aliasing = true
	layer.draw_style_box(sb, body)
	var p := _pulse()
	var press := Color(GOLD, (0.65 + 0.35 * p) * a)
	var btn := Rect2(at + (Vector2(11.0, 2.0) if right_button else Vector2(2.0, 2.0)), Vector2(9.0, 12.0))
	layer.draw_rect(btn, press, true)
	layer.draw_line(at + Vector2(11.0, 2.0), at + Vector2(11.0, 15.0), Color(INK, 0.8 * a), 1.5)
	layer.draw_line(at + Vector2(2.0, 15.0), at + Vector2(20.0, 15.0), Color(INK, 0.8 * a), 1.5)


func _cue_reload() -> void:
	var me = _me()
	if float(me.reloading) > 0.0:
		return
	var a := _fade()
	var f := Fonts.cond(700)
	var size := _px(17)
	var line := "Reload: "
	var w := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var mag_max := int(me.gun.get("mag", 6))
	var box := Vector2(maxf(w + KEY_PX + 30.0, 24.0 + float(mag_max) * 19.0 + 4.0), 74.0)
	var at := _beside(_body(), box)
	_plate(Rect2(at, box), a)
	_text(at + Vector2(12.0, 30.0), line, size, Color(INK, a))
	_key(Rect2(at + Vector2(12.0 + w + 2.0, 8.0), Vector2(KEY_PX, KEY_PX)), "R", _pulse() > 0.55 or _calm, a)
	# the magazine, a pip for each round it holds (the ones it lacks are hollow)
	var pip := 7.0
	var x0 := at.x + 14.0
	for i in mag_max:
		var c := Vector2(x0 + float(i) * (pip * 2.0 + 5.0) + pip, at.y + 56.0)
		if i < int(me.mag):
			layer.draw_circle(c, pip, Color(BRASS, a))
		layer.draw_arc(c, pip, 0.0, TAU, 16, Color(BRASS, a), 2.0, true)
	drawn = "reload"


## A ring on the front door of the nearest house that can be claimed (the tier's pennant and the edge arrows say which it is).
func _cue_find() -> void:
	var door := _nearest_front_door()
	if door == Vector2.INF:
		return
	var a := _fade()
	var c := _s(door)
	var z := _zoom()
	if Rect2(Vector2.ZERO, _view()).grow(-24.0).has_point(c):
		_ring(c, maxf(0.85 * z, 22.0), a)
		drawn = "find"


func _nearest_front_door() -> Vector2:
	var me = _me()
	var houses = sim.get("houses")
	if me == null or houses == null:
		return Vector2.INF
	var town: Dictionary = houses.town
	if town.is_empty() or not town.has("start"):
		return Vector2.INF
	var near := Arrival.nearest(town, Vector2(me.x, me.y))
	return Arrival.door_of(town, near) if near >= 0 else Vector2.INF


## The door to go through: from inside, the nearest door of the house she is in with a room behind it that is not seen; from outside, the nearest candidate's front door.
func _cue_door() -> void:
	var a := _fade()
	var rect := _door_rect()
	if not rect.has_area():
		return
	var a_px := _s(rect.position)
	var b_px := _s(rect.end)
	var rc := Rect2(a_px, b_px - a_px)
	if rc.size.x < 14.0:
		rc = Rect2(rc.get_center() - Vector2(7.0, rc.size.y * 0.5), Vector2(14.0, rc.size.y))
	if rc.size.y < 14.0:
		rc = Rect2(rc.get_center() - Vector2(rc.size.x * 0.5, 7.0), Vector2(rc.size.x, 14.0))
	if Rect2(Vector2.ZERO, _view()).grow(40.0).intersects(rc):
		_outline(rc, a)
		if _refused_room() < 0:    # (the refusal marker has its own words on the same door)
			_hint_plate(Vector2(rc.get_center().x, rc.end.y + 12.0), a)
		drawn = "door"


## The door's tiles as a rectangle (tiles), empty when there is none.
func _door_rect() -> Rect2:
	var me = _me()
	var houses = sim.get("houses")
	var clearing = sim.get("clearing")
	if me == null or houses == null:
		return Rect2()
	var here := Vector2(me.x, me.y)
	var h := int(houses.house_at(me.x, me.y))
	if h < 0:
		var front := _nearest_front_door()
		if front == Vector2.INF:
			return Rect2()
		var near := Arrival.nearest(houses.town, here)
		for d in houses.doors_of(near):
			if bool(d.get("exterior", false)):
				var r := _tiles_rect(d)
				if r.has_area() and r.get_center().distance_to(front) < 3.0:
					return r
		return Rect2(front - Vector2(0.5, 0.5), Vector2(1, 1))
	var best := Rect2()
	var best_d := INF
	for d in houses.doors_of(h):
		if bool(d.get("exterior", false)) or clearing == null:
			continue
		var unseen := false
		for r in _sides(d):
			if not clearing.is_revealed(int(r)):
				unseen = true
		if not unseen:
			continue
		var rc := _tiles_rect(d)
		var dist := rc.get_center().distance_to(here)
		if rc.has_area() and dist < best_d:
			best_d = dist
			best = rc
	return best


func _tiles_rect(d: Dictionary) -> Rect2:
	var tiles = d.get("tiles", [])
	if not (tiles is Array) or (tiles as Array).is_empty():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in tiles:
		lo = Vector2(minf(lo.x, float(t.x)), minf(lo.y, float(t.y)))
		hi = Vector2(maxf(hi.x, float(t.x) + 1.0), maxf(hi.y, float(t.y) + 1.0))
	return Rect2(lo, hi - lo)


## The rooms on the sides of a door (the floor beside any tile of its doorway; never the street).
func _sides(d: Dictionary) -> Array:
	var houses = sim.get("houses")
	var out: Array = []
	for t in d.get("tiles", []):
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var r := int(houses.room_at(float(t.x + o.x) + 0.5, float(t.y + o.y) + 0.5))
			if r >= 0 and not out.has(r):
				out.append(r)
	return out


## A "?" over the first container nobody has searched in the room she is in.
func _cue_search() -> void:
	var c := _search_target()
	if c.is_empty():
		return
	var a := _fade() * float(c.alpha)
	var z := _zoom()
	var at := _s(Vector2(c.at)) + Vector2(0.0, -0.62 * z)
	if not _calm:
		at.y -= 4.0 * sin(_now * TAU * 1.1)
	var r := 12.0
	layer.draw_circle(at, r + 2.5, Color(DARK, 0.85 * a))
	layer.draw_circle(at, r, Color(GOLD, a))
	var f := Fonts.cond(700)
	var size := _px(19)
	var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	layer.draw_string(f, at + Vector2(-w * 0.5, float(size) * 0.34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(DARK, a))
	layer.draw_colored_polygon(PackedVector2Array([at + Vector2(-5, r - 1), at + Vector2(5, r - 1), at + Vector2(0, r + 6)]), Color(GOLD, a))
	_hint_plate(at + Vector2(0.0, r + 10.0), a)
	drawn = "search"


## {"at": the furniture, "alpha"}: the first unsearched container of the avatar's room, else (dimmer) the nearest of her house; {} with none.
func _search_target() -> Dictionary:
	var me = _me()
	var houses = sim.get("houses")
	var search = sim.get("search")
	if me == null or houses == null or search == null:
		return {}
	var h := int(houses.house_at(me.x, me.y))
	if h < 0:
		return {}
	var room := int(houses.room_at(me.x, me.y))
	var here := Vector2(me.x, me.y)
	var best := {}
	var best_d := INF
	for c in houses.containers_of(h):
		if search.is_looted(String(c.id)):
			continue
		if room >= 0 and int(c.get("room", -2)) == room:
			return {"at": Vector2(c.get("at", c.pos)), "alpha": 1.0}
		var d := here.distance_to(Vector2(c.pos))
		if d < best_d:
			best_d = d
			best = {"at": Vector2(c.get("at", c.pos)), "alpha": 0.6}
	return best


## A ring at the spot where E claims.
func _cue_claim() -> void:
	var base = sim.get("base")
	var sc = _scenario()
	if base == null or sc == null or bool(base.claimed):
		return
	var spot: Vector2 = base.spot_of(int(sc.work_house()))
	if spot == Vector2.ZERO:
		return
	var c := _s(spot)
	if Rect2(Vector2.ZERO, _view()).grow(-20.0).has_point(c):
		_ring(c, maxf(0.7 * _zoom(), 20.0), _fade())
		drawn = "claim"


## EARLY: the build lesson's cue. Phase "page": the way to the Build page, step by step (the radio's button while the panel is shut, the Build tab while it is on another page, the NEXT card's button once it is on the Build
## page). Phase "site": a ring on the section waiting for her hands (the nearest to her), with "Hold E here" (the E prompt takes over when she is in reach).
func _cue_build() -> void:
	var a := _fade()
	if cue_phase == "site":
		var bh = sim.get("build_hands")
		var me = _me()
		if bh == null or me == null:
			return
		var here := Vector2(me.x, me.y)
		var best := Vector2.INF
		var best_d := INF
		for e in bh.sites():
			var r: Rect2i = e.rect
			var p := Vector2(clampf(here.x, float(r.position.x), float(r.end.x)), clampf(here.y, float(r.position.y), float(r.end.y)))
			if p.distance_to(here) < best_d:
				best_d = p.distance_to(here)
				best = p
		if best == Vector2.INF:
			return
		var c := _s(best)
		var z := _zoom()
		if Rect2(Vector2.ZERO, _view()).grow(-24.0).has_point(c):
			_ring(c, maxf(0.9 * z, 22.0), a, best_d <= 2.6)
			if best_d > 2.6:
				_hint_text_plate(c + Vector2(0.0, maxf(0.9 * z, 22.0) + 10.0), "Hold E here to build", a)
			drawn = "build"
		else:
			_edge_chevron(c, a)
			drawn = "build"
		return
	var node := _build_page_node()
	if node == null:
		return
	var rc := Rect2(node.get_global_rect().position - layer.get_global_rect().position, node.size)
	if not rc.has_area():
		return
	_top_rect = rc    # (drawn over the HUD's boards: `_draw_top`)
	_top_a = a
	drawn = "build"


## The control the build lesson points at (null when there is none to point at).
func _build_page_node() -> Control:
	var panel = hud.get("radio_panel")
	var node = null
	if hud.has_method("radio_open") and bool(hud.radio_open()) and panel != null:
		if String(hud.radio_page()) == "build":
			var page = panel.page_node("build")
			var nc = page.get("next_card") if page != null else null
			if nc is Dictionary and (nc as Dictionary).get("action") is Control:
				node = nc.action
		elif panel.get("tabs") is Dictionary:
			node = (panel.tabs as Dictionary).get("build")
	else:
		node = hud.get("build_button")    # (the hammer in the toolbar: N)
	if node is Control and is_instance_valid(node) and (node as Control).is_visible_in_tree():
		return node
	return null


## EARLY: the cue of a hint (the card says "HINT"): the thing, and one line on it.
func _cue_hint() -> void:
	match cue:
		"door":
			_cue_door()
		"search":
			_cue_search()
		"clear":
			_cue_clear()


## A ring on the middle of the nearest room of the house in hand that is not clear.
func _cue_clear() -> void:
	var sc = _scenario()
	var rooms: Dictionary = sc._rooms_progress() if sc != null and sc.has_method("_rooms_progress") else {}
	var at = rooms.get("at")
	if not (at is Vector2):
		return
	var a := _fade()
	var c := _s(at)
	var z := _zoom()
	if Rect2(Vector2.ZERO, _view()).grow(-24.0).has_point(c):
		_ring(c, maxf(1.1 * z, 24.0), a)
		_hint_plate(c + Vector2(0.0, maxf(1.1 * z, 24.0) + 8.0), a)
	else:
		_edge_chevron(c, a)
	drawn = "clear"


## The one line of a hint, on a plate whose top middle is at `px`.
func _hint_plate(px: Vector2, a: float) -> void:
	_hint_text_plate(px, _hint_line, a)


func _hint_text_plate(px: Vector2, line: String, a: float) -> void:
	if line == "":
		return
	var f := Fonts.cond(700)
	var size := _px(15)
	var w := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var vp := _view()
	var rc := Rect2(Vector2(clampf(px.x - w * 0.5 - 8.0, PAD, maxf(vp.x - w - 16.0 - PAD, PAD)), clampf(px.y, 70.0, maxf(vp.y - 100.0, 70.0))), Vector2(w + 16.0, float(size) + 10.0))
	_plate(rc, a)
	layer.draw_string(f, rc.position + Vector2(8.0, float(size) + 1.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, a))


## A ring round the first card of the crew (the avatar's own is the first card: the next one is the crew's).
func _cue_ask() -> void:
	var card_rect := _first_crew_card()
	if not card_rect.has_area():
		return
	_outline(card_rect, _fade())
	drawn = "ask"


func _first_crew_card() -> Rect2:
	var cards = hud.get("cards")
	if not (cards is Array):
		return Rect2()
	var pid := String(sim.get("player_id"))
	for c in cards:
		if c.get("p") == null or String(c.p.id) == pid or bool(c.p.dead):
			continue
		var node: Control = c.card
		if node != null and is_instance_valid(node) and node.is_visible_in_tree():
			return Rect2(node.get_global_rect().position - layer.get_global_rect().position, node.size)
	return Rect2()


# --------------------------------------------------------------------- the refusal marker --

## While the claim is refused for a room not yet looked into: a ring on that room's doorway.
func _draw_refusal() -> void:
	var room := _refused_room()
	if room < 0:
		return
	var houses = sim.get("houses")
	var me = _me()
	var here := Vector2(me.x, me.y)
	var h := int(houses.house_at(me.x, me.y))
	var best := Vector2.INF
	var best_d := INF
	for d in houses.doors_of(h):
		if not _sides(d).has(room):
			continue
		var rc := _tiles_rect(d)
		if rc.has_area() and rc.get_center().distance_to(here) < best_d:
			best_d = rc.get_center().distance_to(here)
			best = rc.get_center()
	if best == Vector2.INF:
		var rr = houses.room(room).get("rect", Rect2i())
		best = Vector2(Rect2i(rr).get_center())
	var c := _s(best)
	var z := _zoom()
	var a := 1.0 if _calm else clampf((_now - maxf(_refusal_until - REFUSAL_S, 0.0)) / FADE_S, 0.3, 1.0)
	_ring(c, maxf(0.8 * z, 22.0), a, true)
	var name := String(houses.room(room).get("name", "room"))
	var line := "Look in the %s" % name
	var f := Fonts.cond(700)
	var size := _px(15)
	var w := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var rc2 := Rect2(c + Vector2(-w * 0.5 - 8.0, maxf(0.8 * z, 22.0) + 10.0), Vector2(w + 16.0, float(size) + 10.0))
	_plate(rc2, a)
	layer.draw_string(f, rc2.position + Vector2(8.0, float(size) + 1.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, a))
	drawn += " refusal"


## The room the claim is refused for: the first one not looked into, while she is in a house to claim at its claim spot (the prompt shows the refusal there) or has just pressed E there. -1 for none.
func _refused_room() -> int:
	var houses = sim.get("houses")
	var clearing = sim.get("clearing")
	var base = sim.get("base")
	var me = _me()
	if houses == null or clearing == null or base == null or me == null or bool(base.claimed):
		return -1
	var h := int(houses.house_at(me.x, me.y))
	if h < 0:
		return -1
	var spot: Vector2 = base.spot_of(h)
	var at_spot := spot != Vector2.ZERO and Vector2(me.x, me.y).distance_to(spot) <= float(base.CLAIM_REACH)
	if not at_spot and _now > _refusal_until:
		return -1
	var can: Dictionary = clearing.claimable(h)
	if bool(can.ok) or not String(can.why).begins_with("You have not looked in the "):
		return -1
	for r in houses.rooms_of(h):
		if not clearing.is_revealed(int(r)):
			return int(r)
	return -1


# ------------------------------------------------------------------------------ the box --

## The ammo box of the opening: a crate on the pavement (olive, with brass rounds on the lid), a ring and its name when she is near it; gone when it is taken.
func _draw_box() -> void:
	var op = _opening()
	if op == null or bool(op.box_taken) or op.box_at == Vector2.INF:
		return
	var p := _s(op.box_at)
	if not Rect2(Vector2.ZERO, _view()).grow(80.0).has_point(p):
		return
	var z := _zoom()
	var size := clampf(0.95 * z, 24.0, 90.0)
	var half := Vector2(size, size) * 0.5
	layer.draw_circle(p + Vector2(3.0, 5.0), size * 0.46, Color(0, 0, 0, 0.22))
	if _crate != null:
		layer.draw_texture_rect(_crate, Rect2(p - half, Vector2(size, size)), false, Color(0.72, 0.84, 0.58))
	else:
		layer.draw_rect(Rect2(p - half, Vector2(size, size)), Color(0.34, 0.4, 0.22), true)
	# three brass rounds on the lid
	for i in 3:
		var x := p.x + (float(i) - 1.0) * size * 0.2
		layer.draw_rect(Rect2(Vector2(x - size * 0.045, p.y - size * 0.16), Vector2(size * 0.09, size * 0.24)), BRASS, true)
		layer.draw_rect(Rect2(Vector2(x - size * 0.045, p.y - size * 0.22), Vector2(size * 0.09, size * 0.07)), Color(0.7, 0.2, 0.16), true)
	var me = _me()
	var near: float = Vector2(me.x, me.y).distance_to(op.box_at) if me != null else INF
	if near <= BOX_NEAR:
		_ring(p, size * 0.72, 0.9)
	if near <= BOX_NEAR and near > 2.5:    # (at the box the prompt says it: the name would be over her head)
		var f := Fonts.cond(700)
		var fs := _px(14)
		var w := f.get_string_size("Ammo", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rc := Rect2(p + Vector2(-w * 0.5 - 7.0, -size * 0.72 - 36.0), Vector2(w + 14.0, float(fs) + 8.0))
		_plate(rc, 0.95)
		layer.draw_string(f, rc.position + Vector2(7.0, float(fs) + 1.0), "Ammo", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	drawn += " box"


## "+8 ammo" rising from where the box was, and fading.
func _draw_pops() -> void:
	for pop in _pops:
		var k := clampf(float(pop.age) / POP_S, 0.0, 1.0)
		var at := _s(Vector2(pop.at)) + Vector2(0.0, -30.0 - (0.0 if _calm else 36.0 * k))
		var f := Fonts.cond(700)
		var fs := _px(19)
		var w := f.get_string_size(String(pop.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var a := 1.0 if _calm else (1.0 - smoothstep(0.6, 1.0, k))
		layer.draw_string_outline(f, at + Vector2(-w * 0.5, 0.0), String(pop.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85 * a))
		layer.draw_string(f, at + Vector2(-w * 0.5, 0.0), String(pop.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(GOLD, a))


# ------------------------------------------------------------------------- the rehearsal card --

func _build_card() -> void:
	var st: StyleBox = hud._style(hud.PANEL, 6, Color(GOLD, 0.8), true, "panel_slim")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 8
		st.content_margin_bottom = 9
	card = hud._panel(st)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size.x = 292.0
	card.visible = false
	var col: VBoxContainer = hud._vbox(6)
	card.add_child(col)
	card_label = hud._label("", Fonts.sans(600), 15, hud.INK)
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.custom_minimum_size.x = 40
	col.add_child(card_label)
	var row: HBoxContainer = hud._hbox(8)
	var show := RadioKit.small_button(hud, String(_data("rehearsal.button", "Show me")), 28.0, 15)
	show.tooltip_text = "Open the Build page, where the fence and the gate are ordered"
	show.pressed.connect(_show_me)
	row.add_child(show)
	var later := RadioKit.small_button(hud, "Later", 28.0, 15)
	later.tooltip_text = "Put this away. N opens the Build page any time"
	later.pressed.connect(_hide_card)
	row.add_child(later)
	col.add_child(row)
	var at := 1
	var th = _hud_part()
	if th != null and th.get("obj_card") != null:
		at = int(th.obj_card.get_index()) + 1
	hud.left_col.add_child(card)
	hud.left_col.move_child(card, mini(at, hud.left_col.get_child_count() - 1))


func _data(path: String, fallback = null):
	var sc = _scenario()
	if sc != null and sc.has_method("_cfg"):
		return sc._cfg(path, fallback)
	return fallback


## The first claim: after the banner (a few seconds), if the lessons are on.
func _arm_card() -> void:
	var th = _hud_part()
	if rehearsed or (th != null and not bool(th.lessons_are_on())):
		return
	rehearsed = true
	card_armed = _now + 3.5


func _show_card() -> void:
	if card == null:
		return
	card_label.text = String(_data("rehearsal.text", "The dead come at the bell. Fortify before dark: N opens the Build page."))
	RadioKit.wrap_at(card_label, 268.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.visible = true
	card_left = float(_data("rehearsal.show_s", 14.0))
	card_armed = -1.0
	rehearsed = true
	_confirm_sound()


func _hide_card() -> void:
	card_left = 0.0
	if card != null:
		card.visible = false


func _show_me() -> void:
	if hud != null and hud.has_method("open_radio") and String(hud.radio_page()) != "build":
		hud.open_radio("build")
	_hide_card()


func _step_card(dt: float) -> void:
	if card == null:
		return
	if card_armed >= 0.0 and _now >= card_armed:
		_show_card()
	if card_left > 0.0:
		card_left -= dt
		# (the page is open: the card has done its job)
		if card_left <= 0.0 or String(hud.radio_page()) == "build":
			_hide_card()
