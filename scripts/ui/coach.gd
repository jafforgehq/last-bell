## The coach of Orientation Day: a teacher's overlay above the HUD. It reads the lessons from
## assets/data/tutorial.json, one card at a time, and moves on when the game says the lesson was
## done (the conditions in scripts/tutorial_conditions.gd read the rules' state and what the
## player did). The scenario it teaches in is scripts/sim/orientation.gd.
##
## What it does:
## - A card (made with the HUD's own helpers, so it wears the HUD's look) with the lesson in a few
##   plain words, the step's goal, progress dots and a Skip button that is always there. Where a
##   card has a button (Got it, Speed up, and on the last card Start a real run, Replay, Keep
##   playing here) it is the one thing to press.
## - A soft light on what the lesson is about: the screen is dimmed round a ring on a part of the
##   HUD, or a ring on a person or a wall piece in the world. The target is looked up again every
##   frame (the HUD rebuilds its buttons and cards). After 20 seconds of nothing the ring pulses
##   and Show me appears, and Show me (or 45 seconds) brings an arrow.
## - The game waits while a card asks to be read (`pause`), or until the player has done the first
##   part of the step (`pause_until`); the coach holds the speed at 0 the way the Space key does
##   and lets it go afterwards.
## - A soft lock: while a step is up, orders it does not teach are refused with a gentle toast
##   ("Not yet: first select Ruth."), and the order buttons it does not teach are ghosted. The
##   camera, pausing, saving and loading, and Esc always work. The gate is `allows`, which
##   main.gd asks (`_allows`) in its input handlers while a coach exists.
## - Steps may wait for their moment (`start`), bring a beat of the scenario when they begin
##   (`fire`), move the camera (`focus`, `follow`) and clear the selection.
## - Over a page of the HUD (the scavenging dialog, the Duty roster) a step that has a line for it (a
##   `dialog_text`, or a `line` on its goals) shrinks its card to that one line at the top of the window,
##   and the coach adds no dim of its own (the page has its veil) and offers no Show me (the ring pulses
##   and the arrow comes by itself); the ring goes on the page's own buttons (`jobs.auto`, `dialog.send`...).
## - It is the scenario that remembers where it is (`step`, `coach_state`), so a save made in the
##   middle resumes the same step.
##
## Orientation Day is taught in the game the player will play: with the avatar (round 17: walking, aiming and shooting, the
## ladder, the radio, the News and its calls, the map, the alarm) from assets/data/tutorial.json, or, in the old yard
## (`--noavatar`, a test), from assets/data/tutorial_classic.json (see `steps_path`). The card keeps out of the way of the
## person the player plays, and of the gun's readout, as well as of the thing it points at (`best_rect`).
##
## It does nothing in a normal run: main.gd builds it only for Orientation Day, and every call
## into it is behind `if coach != null`.
extends CanvasLayer

const Fonts := preload("res://scripts/ui/fonts.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Prefs := preload("res://scripts/prefs.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const STEPS_PATH := "res://assets/data/tutorial.json"
## The old yard's lesson (the one with no avatar: orders by right-click and by the keys).
const CLASSIC_PATH := "res://assets/data/tutorial_classic.json"
## The card's width, the space kept round the window's edge and round the target.
const CARD_W := 360.0
const EDGE := 12.0
const GAP := 16.0
## Real seconds of nothing before the ring pulses (and Show me appears), and before the arrow comes.
const IDLE_PULSE_S := 20.0
const IDLE_ARROW_S := 45.0
## The crew of the real run the last card offers: what the New game screen opens on.
const REAL_CREW := 5
## A card stays at least this long when its lesson is already done as it begins, so it does not
## blink past.
const MIN_SHOW_S := 1.0
## How long the check mark shows when a lesson is done.
const DONE_FLASH_S := 0.7
## How long the camera is eased towards what a step asks it to look at.
const FOCUS_S := 1.6
## What a pixel of the card over the person the player plays (or the gun's readout) costs in `best_rect`, against 1 for a pixel over
## a panel of the HUD and 50 over the thing a card points at.
const KEEP_WEIGHT := 400.0
## What it is worth to a card in avatar mode to stay where it is rather than move to another place.
const STAY_BONUS := 6000.0
## How far round the person the player plays, in tiles, the card keeps clear (the figure, the YOU tag and the gun's muzzle).
const AVATAR_CLEAR := 1.2
## How dark the screen goes round a lit part of the HUD.
const DIM := 0.4
## The most words a card may have (the data test holds the lessons to it).
const MAX_WORDS := 35
## What always works, whatever the step: looking, saving and loading, and following someone
## with the camera.
const ALWAYS := ["camera", "save", "load", "gizmo:focus", "select:none"]

## The soft hole in the dim: a rounded box of the target's size, darkest far from it.
const DIM_SHADER := """
shader_type canvas_item;
uniform vec4 hole = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 area = vec2(1280.0, 800.0);
uniform float pad = 6.0;
uniform float radius = 10.0;
uniform float soft = 22.0;
uniform float strength = 0.4;

float round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * area;
	vec2 c = hole.xy + hole.zw * 0.5;
	float d = round_box(px - c, hole.zw * 0.5 + vec2(pad), radius);
	COLOR = vec4(0.02, 0.03, 0.03, smoothstep(0.0, soft, d) * strength);
}
"""


## The progress dots: one for each step, the done ones filled, the present one gold.
class Dots:
	extends Control
	var count := 0
	var at := 0
	var ink := Color("#eeeadd")
	var accent := Color("#f0c24a")

	func _draw() -> void:
		if count <= 0:
			return
		var step := minf(11.0, size.x / float(count))
		var r := clampf(step * 0.3, 2.0, 3.5)
		var y := size.y * 0.5
		for i in count:
			var c := Vector2(r + 1.0 + step * i, y)
			if i == at:
				draw_circle(c, r + 1.5, accent)
			elif i < at:
				draw_circle(c, r, Color(ink, 0.85))
			else:
				draw_arc(c, r - 0.5, 0.0, TAU, 12, Color(ink, 0.4), 1.2, true)


## The light on the target: a ring (a rounded box, or a circle for a person), pulsing when asked,
## an arrow when asked, and an arrow at the window's edge when the target is out of sight.
class Spot:
	extends Control
	var rect := Rect2()
	var circle := false
	var pulse := false
	var arrow := false
	## The card, which the arrow keeps out from under, and whether the player asked for less motion.
	var avoid := Rect2()
	var reduce_motion := false
	var t := 0.0
	var ring := Color("#f0c24a")
	var back := Color(0.04, 0.04, 0.03, 0.85)
	## The window the target has to be in to be drawn there (else an arrow at its edge shows the way).
	var view := Rect2()

	func _draw() -> void:
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		if view.size.x > 0.0 and not view.intersects(rect):
			_edge_arrow()
			return
		var k := 0.0
		if pulse:
			k = 0.5 if reduce_motion else 0.5 + 0.5 * sin(t * 5.0)
		var pad := 6.0 + 3.0 * k
		var r := rect.grow(pad)
		if circle:
			var c := rect.get_center()
			var rad := maxf(rect.size.x, rect.size.y) * 0.5 + pad
			draw_arc(c, rad + 5.0, 0.0, TAU, 56, Color(ring, 0.18 + 0.12 * k), 8.0, true)
			draw_arc(c, rad, 0.0, TAU, 56, Color(ring, 0.8 + 0.2 * k), 3.0 + 1.5 * k, true)
		else:
			_box(r.grow(4.0), Color(ring, 0.18 + 0.12 * k), 8.0, 12.0)
			_box(r, Color(ring, 0.8 + 0.2 * k), 3.0 + 1.5 * k, 8.0)
		if arrow:
			_draw_arrow(r)

	func _box(r: Rect2, color: Color, width: float, radius: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(int(ceil(width)))
		sb.set_corner_radius_all(int(radius))
		sb.border_color = color
		sb.anti_aliasing = true
		draw_style_box(sb, r)

	## A chunky arrow that bobs towards the ring, coming from the side that has room and is not
	## under the card.
	func _draw_arrow(r: Rect2) -> void:
		var bob := 5.0 if reduce_motion else 5.0 + 5.0 * sin(t * 6.0)
		var dir := _arrow_dir(r)
		var edge := _edge_point(r, dir)
		var tip := edge + dir * (4.0 + bob)
		var side := Vector2(-dir.y, dir.x)
		var head := PackedVector2Array([tip, tip + dir * 22.0 + side * 13.0, tip + dir * 22.0 - side * 13.0])
		var shaft := PackedVector2Array([tip + dir * 20.0 + side * 5.0, tip + dir * 46.0 + side * 5.0, tip + dir * 46.0 - side * 5.0, tip + dir * 20.0 - side * 5.0])
		for poly in [shaft, head]:
			draw_colored_polygon(_grown(poly, 2.5), back)
		for poly in [shaft, head]:
			draw_colored_polygon(poly, ring)

	## The way the arrow comes from (the direction from the target out to its tail): the one of eight
	## that keeps it inside the window and out from under the card, preferring the side away from
	## the card.
	func _arrow_dir(r: Rect2) -> Vector2:
		var c := r.get_center()
		var away := Vector2(0, -1)
		if avoid.size.x > 0.0 and avoid.get_center().distance_to(c) > 1.0:
			away = (c - avoid.get_center()).normalized()
		var best := away
		var best_cost := INF
		for i in 8:
			var d := Vector2.from_angle(TAU * float(i) / 8.0)
			var base := _edge_point(r, d)
			var box := Rect2(base, Vector2.ZERO).expand(base + d * 62.0).grow(16.0)
			var cost := (1.0 - d.dot(away)) * 40.0
			if view.size.x > 0.0 and not view.grow(-4.0).encloses(box):
				cost += 1000.0
			if avoid.size.x > 0.0 and avoid.intersects(box):
				cost += 1000.0
			if cost < best_cost:
				best_cost = cost
				best = d
		return best

	## Where a ray from the centre of `r` towards `dir` leaves it (away from the centre): the box
	## itself, or for a circle the circle.
	func _edge_point(r: Rect2, dir: Vector2) -> Vector2:
		var c := r.get_center()
		if circle:
			return c + dir * (r.size.x * 0.5)
		var tx := INF if absf(dir.x) < 0.001 else (r.size.x * 0.5) / absf(dir.x)
		var ty := INF if absf(dir.y) < 0.001 else (r.size.y * 0.5) / absf(dir.y)
		return c + dir * minf(tx, ty)

	func _grown(poly: PackedVector2Array, by: float) -> PackedVector2Array:
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= float(poly.size())
		var out := PackedVector2Array()
		for p in poly:
			out.append(p + (p - c).normalized() * by)
		return out

	## The target is out of the window: a gold chevron on the edge, towards it.
	func _edge_arrow() -> void:
		var inset := view.grow(-34.0)
		var c := view.get_center()
		var to := rect.get_center() - c
		if to.length() < 1.0:
			return
		var dir := to.normalized()
		var tx := INF if absf(dir.x) < 0.001 else (inset.size.x * 0.5) / absf(dir.x)
		var ty := INF if absf(dir.y) < 0.001 else (inset.size.y * 0.5) / absf(dir.y)
		var at := c + dir * minf(tx, ty)
		var side := Vector2(-dir.y, dir.x)
		var bob := 0.0 if reduce_motion else 3.0 * sin(t * 6.0)
		var tip := at + dir * (14.0 + bob)
		var head := PackedVector2Array([tip, tip - dir * 24.0 + side * 15.0, tip - dir * 24.0 - side * 15.0])
		draw_colored_polygon(_grown(head, 2.5), back)
		draw_colored_polygon(head, ring)


var main
var hud
var sim
var scenario

## The steps in play (those whose `needs` the game meets), the present one and its place in the
## list, and where it is: "wait" (the step's `start` has not come), "active", "done" (the check
## mark), "wrap" (the last card) or "ended".
var steps: Array = []
var index := -1
var step := {}
var phase := "idle"
## What the coach keeps for the step: see tutorial_conditions.gd. It is the scenario's
## `coach_state` itself, so it is saved with the run.
var state := {}
## The card at the end was reached by Skip rather than by finishing.
var skipped := false
## The coach holds the game still (speed 0) and the speed the player had before.
var held := false
var held_speed := 1
## Real seconds without anything from the player on a step, and whether the arrow was asked for.
var idle_t := 0.0
var arrow_asked := false
## The anchor that is lit now (its name and its rectangle in canvas pixels; empty when none).
var target_name := ""
var target_rect := Rect2()

var card: PanelContainer
var title_label: Label
var text_label: Label
var goal_label: Label
var dots: Dots
var skip_button: Button
var show_button: Button
var next_button: Button
var speed_button: Button
var wrap_box: VBoxContainer
var real_button: Button
var replay_button: Button
var stay_button: Button
var spot: Spot
var dim_rect: ColorRect
var _dim_material: ShaderMaterial

var _clock := 0.0
var _done_t := 0.0
var _focus_to = null
var _focus_t := 0.0
var _toast_text := ""
var _toast_at := -10.0
var _card_key := ""
var _fade := 0.0
## Where the card is (going) to be, so the arrow keeps out from under it.
var _card_rect := Rect2()
## How many things the player did that the soft lock refused (for the tests).
var refused := 0


# ------------------------------------------------------------------- data --

## The file the lessons are read from: the avatar's, or the old yard's.
static func steps_path(avatar: bool) -> String:
	return STEPS_PATH if avatar else CLASSIC_PATH


## The steps of the file (an empty list, and an error, when it cannot be read).
static func load_steps(path: String = STEPS_PATH) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("steps")) != TYPE_ARRAY:
		push_error("Could not read the tutorial steps from %s" % path)
		return []
	return parsed.steps


## Every anchor name the steps use (the targets, the ones they point at while they wait, and the
## ones an anchor chooses between).
static func anchor_names(all_steps: Array) -> Array:
	var names: Array = []
	for s in all_steps:
		for key in ["anchor", "wait_anchor"]:
			for entry in s.get(key, []):
				var n := String(entry.name) if typeof(entry) == TYPE_DICTIONARY else String(entry)
				if not names.has(n):
					names.append(n)
	return names


## The key of a selection for the lock and for what the player did: "person:ruth", "segment:3",
## "zombie", or "none".
static func sel_key(sel) -> String:
	if sel == null:
		return "none"
	match String(sel.kind):
		"person":
			return "person:%s" % sel.ref.id
		"segment":
			return "segment:%d" % int(sel.ref.id)
	return String(sel.kind)


## Whether an allow-list pattern covers a key: the same words, `*` for any one word, and a
## `*` at the end for everything from there on ("select:*" covers "select:person:ruth").
static func covers(pattern: String, key: String) -> bool:
	if pattern == "*":
		return true
	var p := pattern.split(":")
	var k := key.split(":")
	for i in p.size():
		if p[i] == "*":
			if i == p.size() - 1:
				return k.size() > i
			if i >= k.size():
				return false
			continue
		if i >= k.size() or p[i] != k[i]:
			return false
	return p.size() == k.size()


## How many words a card's text has.
static func words(text: String) -> int:
	var n := 0
	for w in text.split(" ", false):
		if w.strip_edges() != "":
			n += 1
	return n


# ------------------------------------------------------------------ set up --

## Builds the coach over the game: `game` is main.gd, `game_hud` its HUD and `game_sim` the rules
## (whose scenario is Orientation Day). `all_steps` are the lessons (load_steps).
func setup(game, game_hud, game_sim, all_steps: Array) -> void:
	main = game
	hud = game_hud
	sim = game_sim
	scenario = sim.scenario
	for s in all_steps:
		if _available(s):
			steps.append(s)
	layer = 4
	name = "Coach"
	_build()
	scenario.coached = true
	# the HUD's one-line hint says the same basics: the coach replaces it
	hud.set("hint_spent", true)
	if hud.hint != null:
		hud.hint.visible = false
	hud.set_locked(Callable(self, "would_allow"))


## Whether the game has what a step needs ("workshop": the worktable).
func _available(s: Dictionary) -> bool:
	match String(s.get("needs", "")):
		"workshop":
			return sim.get("workshop") != null and sim.d.has("workshop")
	return true


## Starts teaching: from the step the scenario was left at (a fresh run, or a loaded save), or
## from step `at` when that is above zero (the world is put the way that step expects).
func begin(at: int = -1) -> void:
	if steps.is_empty():
		_end()
		return
	if at > 0:
		at = mini(at, steps.size() - 1)
		_jump(at)
		_begin(at)
		_update_hold()
		return
	var i := clampi(scenario.step, 0, steps.size() - 1)
	var saved: Dictionary = scenario.coach_state
	if not saved.is_empty() and String(saved.get("step", "")) == String(steps[i].id):
		_resume(i, saved)
	else:
		_begin(i)
	_update_hold()


## Puts the world the way step `at` expects, for starting there.
func _jump(at: int) -> void:
	var spec: Dictionary = steps[at].get("jump", {})
	scenario.jump(spec)
	var who := String(spec.get("select", ""))
	if who != "":
		for p in sim.people:
			if p.id == who:
				main._select({"kind": "person", "ref": p})


func _build() -> void:
	spot = Spot.new()
	spot.name = "Spot"
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spot.ring = hud.ACCENT
	var shader := Shader.new()
	shader.code = DIM_SHADER
	_dim_material = ShaderMaterial.new()
	_dim_material.shader = shader
	dim_rect = ColorRect.new()
	dim_rect.name = "Dim"
	dim_rect.color = Color.WHITE
	dim_rect.material = _dim_material
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim_rect.visible = false
	add_child(dim_rect)
	add_child(spot)

	card = hud._panel()
	card.name = "Card"
	card.custom_minimum_size.x = CARD_W
	card.visible = false
	var col: VBoxContainer = hud._vbox(8)
	var top: HBoxContainer = hud._hbox(8)
	dots = Dots.new()
	dots.custom_minimum_size = Vector2(0, 14)
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.ink = hud.INK
	dots.accent = hud.ACCENT
	top.add_child(dots)
	skip_button = _link_button("Skip tutorial")
	skip_button.pressed.connect(skip)
	top.add_child(skip_button)
	col.add_child(top)
	title_label = hud._label("", Fonts.cond(700), 22, hud.INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title_label)
	text_label = hud._label("", Fonts.sans(400), 15, hud.INK)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(text_label)
	goal_label = hud._label("", Fonts.sans(600), 14, hud.ACCENT)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(goal_label)
	var buttons: HBoxContainer = hud._hbox(8)
	show_button = hud._button("Show me", false)
	show_button.custom_minimum_size = Vector2(96, 36)
	show_button.pressed.connect(func(): arrow_asked = true)
	buttons.add_child(show_button)
	buttons.add_child(hud._spacer())
	speed_button = hud._button("Speed up", true)
	speed_button.custom_minimum_size = Vector2(96, 36)
	speed_button.pressed.connect(_speed_up)
	buttons.add_child(speed_button)
	next_button = hud._button("Got it", true)
	next_button.custom_minimum_size = Vector2(96, 36)
	next_button.pressed.connect(press_next)
	buttons.add_child(next_button)
	col.add_child(buttons)
	# the last card's buttons: the real run on its own line, the other two beside each other
	var wrap_col: VBoxContainer = hud._vbox(8)
	wrap_box = wrap_col
	real_button = hud._button("Start a real run", true)
	real_button.pressed.connect(start_real_run)
	wrap_col.add_child(real_button)
	var wrap_row: HBoxContainer = hud._hbox(8)
	replay_button = hud._button("Replay", false)
	replay_button.pressed.connect(replay)
	replay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap_row.add_child(replay_button)
	stay_button = hud._button("Keep playing here", false)
	stay_button.pressed.connect(keep_playing)
	stay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap_row.add_child(stay_button)
	wrap_col.add_child(wrap_row)
	col.add_child(wrap_col)
	card.add_child(col)
	add_child(card)


## A quiet text button, for Skip.
func _link_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Fonts.sans(600))
	b.add_theme_font_size_override("font_size", 13)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, hud.INK3 if key == "font_color" else hud.INK)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# -------------------------------------------------------------- the steps --

func current_step() -> Dictionary:
	return step


## The id of the present step ("" before the first and after the last).
func step_id() -> String:
	return String(step.get("id", ""))


func _begin(i: int) -> void:
	index = i
	step = steps[i]
	scenario.step = i
	state = {"step": String(step.id), "phase": "wait", "t": 0.0, "pan": 0.0, "zoom": 0.0, "did": {}, "events": {}, "next": false, "base": {}}
	scenario.coach_state = state
	idle_t = 0.0
	arrow_asked = false
	_refresh_state()
	if _start_met():
		_activate()
	else:
		phase = "wait"
		state["phase"] = "wait"
		_card_key = ""


## A lesson that was under way when the game was saved, picked up again.
func _resume(i: int, saved: Dictionary) -> void:
	index = i
	step = steps[i]
	state = saved
	scenario.coach_state = state
	idle_t = 0.0
	arrow_asked = false
	phase = String(state.get("phase", "active"))
	if phase == "done":
		_advance()
		return
	if phase == "wrap":
		skipped = bool(state.get("skipped", false))
	_card_key = ""


func _start_met() -> bool:
	return Conditions.check(step.get("start", {}), sim, state)


## The step begins: what it asks of the world is done, and its card goes up.
func _activate() -> void:
	phase = "wrap" if String(step.get("type", "")) == "wrap" else "active"
	state["phase"] = phase
	state["t"] = 0.0
	var pos := {}
	for p in sim.people:
		pos[p.id] = [p.x, p.y]
	state["base"] = {"ammo": float(sim.stock.ammo), "kills": float(sim.kills), "pos": pos, "news": float(sim.radio.latest_id())}
	var me = sim.avatar.player()
	if me != null:
		# (numbers as a save gives them back: floats)
		state["base"]["mine"] = {"shots": float(me.stats.shots), "kills": float(me.stats.kills)}
	for id in step.get("fire", []):
		scenario.fire(String(id))
	# a lesson that is already done as it begins stays up a moment (MIN_SHOW_S) so it can be read;
	# one the player does is done at once
	state["pre"] = Conditions.check(step.get("done", {}), sim, state) if phase == "active" else false
	if bool(step.get("clear_selection", false)) and main.selection != null:
		main._select(null)
	_aim_camera()
	_card_key = ""
	if phase == "wrap":
		Prefs.set_flag("tutorial_done")


func _complete() -> void:
	var done: Dictionary = step.get("done", {})
	if String(done.get("cond", "")) == "next":
		_advance()
		return
	_sound("ui_confirm", 0.5)
	phase = "done"
	state["phase"] = "done"
	_done_t = DONE_FLASH_S
	_card_key = ""


func _advance() -> void:
	_release_camera()
	if index + 1 >= steps.size():
		_end()
		return
	_begin(index + 1)


## A soft menu sound, when the game has the sounds (a test's fake does not).
func _sound(sound_name: String, level: float) -> void:
	var player = main.get("sound")
	if player != null and is_instance_valid(player) and player.has_method("ui"):
		player.ui(sound_name, level)


## The Got it button (or Enter) on a card that waits to be read.
func press_next() -> void:
	if phase == "active" and String(step.get("done", {}).get("cond", "")) == "next":
		state["next"] = true
		_advance()


## Skip: the last card, the one that offers a real run. It sets the flag like finishing does.
func skip() -> void:
	if phase == "ended" or phase == "wrap" or steps.is_empty():
		return
	skipped = true
	_release_camera()
	_begin(steps.size() - 1)
	state["skipped"] = true


## Start a real run (Standard difficulty, a random seed, the crew of five a new game begins with, played by an avatar).
func start_real_run() -> void:
	if phase != "wrap":
		return
	if main.has_method("start_run"):
		main.start_run(1, randi(), REAL_CREW)
	else:
		hud.start_run({"difficulty": 1, "seed": randi(), "crew": REAL_CREW})


## Play Orientation Day again from the start.
func replay() -> void:
	if phase != "wrap":
		return
	if main.has_method("start_tutorial"):
		main.start_tutorial()


## Stay in the yard: the coach goes, the scenario stays (a sandbox that cannot be lost).
func keep_playing() -> void:
	if phase == "wrap":
		_end()


## The coach is done: the game is let go, the lock is lifted, the scenario takes over.
func _end() -> void:
	if phase == "ended":
		return
	phase = "ended"
	_release_hold()
	_release_camera()
	hud.set_locked(Callable())
	scenario.finish()
	scenario.coach_state = {}
	if is_instance_valid(spot):
		spot.rect = Rect2()
	if is_instance_valid(dim_rect):
		dim_rect.visible = false
	if is_instance_valid(card):
		card.visible = false
	if main.get("coach") == self:
		main.coach = null
	queue_free()


# -------------------------------------------------------------- the world --

## What the coach reads of the game each frame, for the conditions.
func _refresh_state() -> void:
	var sel = main.selection
	var s := {}
	if sel != null:
		match String(sel.kind):
			"person":
				s = {"kind": "person", "id": String(sel.ref.id)}
			"segment":
				s = {"kind": "segment", "id": int(sel.ref.id)}
			_:
				s = {"kind": String(sel.kind)}
	state["selection"] = s
	state["speed"] = main.speed
	state["fields"] = main.fields
	var d = hud.scavenge_dialog
	var open: bool = d != null and is_instance_valid(d)
	state["dialog"] = {"open": open, "site": String(d.site_id) if open else ""}
	var page = hud.get("jobs_screen")
	state["jobs"] = {"open": page != null and is_instance_valid(page)}
	state["news"] = {"open": hud.has_method("news_open") and hud.news_open()}


## The player did something (main.gd's _did): `kind` is "select" (with the selection), "move",
## "gizmo" (the order's id), "speed", "pan" (tiles), "zoom" (an amount), "save", "load" or "fields".
func on_did(kind: String, arg = null) -> void:
	idle_t = 0.0
	if phase == "ended" or state.is_empty():
		return
	var did: Dictionary = state["did"]
	match kind:
		"pan":
			state["pan"] = float(state.get("pan", 0.0)) + float(arg)
			_focus_to = null
		"zoom":
			state["zoom"] = float(state.get("zoom", 0.0)) + float(arg)
			return
		"select":
			_count(did, "select:%s" % sel_key(arg))
		"gizmo", "speed":
			_count(did, "%s:%s" % [kind, str(arg)])
		_:
			_count(did, kind)


## The rules produced an event (main.gd forwards every one).
func on_event(e: Dictionary) -> void:
	if phase == "ended" or state.is_empty():
		return
	var type := String(e.get("type", ""))
	_count(state["events"], type)
	# an answer of the radio to a request: who was asked, what, and whether they agreed
	if type == "radio_line":
		_count(state["events"], "radio_line:%s:%s:%s" % [String(e.get("who", "")), String(e.get("verb", "")), "ok" if bool(e.get("ok", false)) else "no"])
	# a job given (an "assigned" event that names a station) counts on its own: taking one away is not giving one
	if type == "assigned" and String(e.get("station", "")) != "":
		_count(state["events"], "assigned:job")


func _count(table: Dictionary, key: String) -> void:
	table[key] = float(table.get(key, 0.0)) + 1.0


## The camera is eased to what a step looks at, or follows someone.
func _aim_camera() -> void:
	_focus_to = null
	var focus := String(step.get("focus", ""))
	if focus != "":
		var at = _world_point(focus)
		if at != null:
			_focus_to = at
			_focus_t = FOCUS_S
	if not hold_wanted():
		_apply_run_speed()
		_start_follow()


## A step where something is to be watched (someone walking, shots, a treatment) runs at the speed
## it names, at most (`run_speed`), so the player can see it: the player may press a faster one.
func _apply_run_speed() -> void:
	var cap := int(step.get("run_speed", 0))
	if cap > 0 and phase == "active" and main.speed > cap:
		main.speed = cap


## The camera follows the person a step names (Hector walking to his post), once the game is
## running; the player's own camera moves end it.
func _start_follow() -> void:
	var who := String(step.get("follow", ""))
	if who == "" or phase != "active":
		return
	for p in sim.people:
		if p.id == who:
			main.follow = p


func _release_camera() -> void:
	_focus_to = null
	var who := String(step.get("follow", ""))
	if who != "" and main.follow != null and main.follow.get("id") == who:
		main.follow = null


func _update_focus(delta: float) -> void:
	if _focus_to == null:
		return
	_focus_t -= delta
	var to: Vector2 = _focus_to
	if String(step.get("follow", "")) == "":
		main.follow = null
	if Prefs.on("ui", "reduce_motion"):
		main.cam_center = to
	else:
		main.cam_center = main.cam_center.lerp(to, 1.0 - exp(-6.0 * delta))
	if _focus_t <= 0.0 or main.cam_center.distance_to(to) < 0.1:
		_focus_to = null


## A point of the map (in tiles) that a world anchor names, or null.
func _world_point(name: String):
	if name.begins_with("person:"):
		var p = _person(name.trim_prefix("person:"))
		return Vector2(p.x, p.y) if p != null and p.away == null else null
	if name.begins_with("wall:"):
		var seg = _wall(int(name.trim_prefix("wall:")))
		return seg.center if seg != null else null
	if name == "bench":
		var shop = sim.get("workshop")
		return shop.bench() if shop != null else null
	if name.begins_with("spot:"):
		var xy := name.trim_prefix("spot:").split(",")
		return Vector2(float(xy[0]), float(xy[1])) if xy.size() == 2 else null
	if name == "zombie:near":
		var z = _nearest_dead()
		return Vector2(z.x, z.y - 0.45) if z != null else null
	return null


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _wall(id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


## The one of the dead that is coming for the compound (or at its wall) nearest the person the player plays (the nearest to the
## camera without an avatar), or null: the thing a lesson on shooting points at.
func _nearest_dead():
	var me = sim.avatar.player()
	var from: Vector2 = Vector2(me.x, me.y) if me != null else main.cam_center
	var best = null
	var best_d := INF
	for z in sim.zombies:
		if z.state != "approach" and z.state != "attack" and z.state != "hunt" and z.state != "breach":
			continue
		var d := Vector2(z.x, z.y).distance_to(from)
		if d < best_d:
			best_d = d
			best = z
	return best


func _is_world(name: String) -> bool:
	return name.begins_with("person:") or name.begins_with("wall:") or name.begins_with("spot:") or name == "bench" or name == "zombie:near"


## The screen rectangle of a world anchor, and whether it is drawn as a circle ({"rect",
## "circle"}), or an empty rectangle when it is not there.
func _world_rect(name: String) -> Dictionary:
	if name.begins_with("person:"):
		var p = _person(name.trim_prefix("person:"))
		if p == null or p.away != null:
			return {"rect": Rect2(), "circle": true}
		var c: Vector2 = main._tile_to_screen(main.view_pos(p) + Vector2(0.0, -0.45))
		var r: float = 0.8 * main.zoom_px
		return {"rect": Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), "circle": true}
	if name.begins_with("wall:"):
		var seg = _wall(int(name.trim_prefix("wall:")))
		if seg == null:
			return {"rect": Rect2(), "circle": false}
		var box: Rect2 = OverlayNode.section_rect(seg)
		var a: Vector2 = main._tile_to_screen(box.position)
		var b: Vector2 = main._tile_to_screen(box.end)
		return {"rect": Rect2(a, b - a).abs(), "circle": false}
	var at = _world_point(name)
	if at == null:
		return {"rect": Rect2(), "circle": true}
	if name == "zombie:near":
		var near = _nearest_dead()
		at = main.view_pos(near) + Vector2(0.0, -0.45)
	var c2: Vector2 = main._tile_to_screen(at)
	var r2: float = 1.0 * main.zoom_px
	return {"rect": Rect2(c2 - Vector2(r2, r2), Vector2(r2, r2) * 2.0), "circle": true}


## Where the ring goes now: the first of the step's anchors whose `when` holds and that can be
## found. {"name", "rect", "circle", "world"}; the rectangle is empty when there is none.
func _resolve(entries: Array) -> Dictionary:
	for entry in entries:
		var name := ""
		if typeof(entry) == TYPE_DICTIONARY:
			name = String(entry.get("name", ""))
			var when := String(entry.get("when", ""))
			if when != "" and not Conditions.check({"cond": when, "params": entry.get("params", {})}, sim, state):
				continue
		else:
			name = String(entry)
		if _is_world(name):
			var w := _world_rect(name)
			if w.rect.size.x > 0.0:
				return {"name": name, "rect": w.rect, "circle": w.circle, "world": true}
		else:
			var r: Rect2 = hud.anchor_rect(name)
			if r.size.x > 0.0 and r.size.y > 0.0:
				return {"name": name, "rect": r, "circle": false, "world": false}
	return {"name": "", "rect": Rect2(), "circle": false, "world": false}


# --------------------------------------------------------------- the game --

## What the step holds the game for: while a card asks to be read, or until the player has done
## the first part of the step.
func hold_wanted() -> bool:
	if phase == "wrap":
		return true
	if phase != "active":
		return false
	if bool(step.get("pause", false)):
		return true
	var until = step.get("pause_until")
	return typeof(until) == TYPE_DICTIONARY and not Conditions.check(until, sim, state)


func _update_hold() -> void:
	if hold_wanted():
		if not held:
			held = true
			held_speed = main.speed
		if main.speed != 0:
			main.speed = 0
	else:
		_release_hold()


func _release_hold() -> void:
	if not held:
		return
	held = false
	if main.speed == 0 and held_speed > 0:
		main.speed = held_speed
	_apply_run_speed()
	_start_follow()


# ---------------------------------------------------------------- the lock --

## The allow list of the present phase: while waiting only looking at people is allowed; on the
## last card everything is.
func _allow_list() -> Array:
	match phase:
		"wait":
			return step.get("wait_allow", ["select:*"])
		"wrap", "ended", "idle":
			return ["*"]
	return step.get("allow", [])


## What the step has to say about `kind` and `arg` (an order's id, a speed, a selection key):
## "" when it is allowed, else the few words of the toast.
func refusal(kind: String, arg = null) -> String:
	if phase == "ended" or phase == "idle" or step.is_empty():
		return ""
	var key := kind if arg == null or kind == "move" else "%s:%s" % [kind, str(arg)]
	if kind == "speed":
		return "The game waits while you read." if int(arg) > 0 and hold_wanted() else ""
	for always in ALWAYS:
		if covers(always, key):
			return ""
	var goal := String(step.get("goal", ""))
	var hint := "Not yet: first %s." % goal if goal != "" and phase != "wait" else "Not yet: let the day go on first."
	if kind == "gizmo" and str(arg) == "sendout":
		return "Not in the tutorial: X sends someone out for good."
	var allow := _allow_list()
	var listed := false
	for pattern in allow:
		if covers(String(pattern), key):
			listed = true
			break
	if not listed:
		return hint
	# an order to walk somewhere: to a spot the step is happy with
	if kind == "move" and typeof(arg) == TYPE_VECTOR2:
		var spot_why := _bad_spot(arg)
		if spot_why != "":
			return spot_why
	# an order is for the person (or wall piece) selected: it has to be one the step allows
	if kind == "gizmo" or kind == "move":
		var sel := sel_key(main.selection)
		var fine := false
		var any_select := false
		for pattern in allow:
			var pat := String(pattern)
			if pat.begins_with("select:") or pat == "*":
				any_select = true
				if covers(pat, "select:%s" % sel):
					fine = true
					break
		if any_select and not fine:
			return hint
	return ""


## Why a spot of the map (in tiles) is not one the step wants someone sent to ("" when it is): outside
## the walls (`move_inside`: x0, y0, x1, y1) or too far from them (`move_radius`).
func _bad_spot(at: Vector2) -> String:
	var box = step.get("move_inside")
	if typeof(box) == TYPE_ARRAY and box.size() == 4:
		if at.x < float(box[0]) or at.y < float(box[1]) or at.x > float(box[2]) or at.y > float(box[3]):
			return "Pick a spot inside the yard."
	var reach := float(step.get("move_radius", 0.0))
	var near := float(step.get("move_min", 0.0))
	var sel = main.selection
	if sel != null and sel.kind == "person":
		var apart := Vector2(sel.ref.x, sel.ref.y).distance_to(at)
		if reach > 0.0 and apart > reach:
			return "Pick a spot a little closer to %s." % sel.ref.first
		if near > 0.0 and apart < near:
			return "Pick a spot a bit further from %s." % sel.ref.first
	return ""


## Whether the player may do this now (no toast): what the HUD asks to ghost its buttons.
func would_allow(kind: String, arg = null) -> bool:
	return refusal(kind, arg) == ""


## The gate main.gd asks before it acts on what the player did: true to go ahead, false (and a
## gentle toast, not more often than every second and a half) when the step does not teach it.
func allows(kind: String, arg = null) -> bool:
	var why := refusal(kind, arg)
	if why == "":
		return true
	refused += 1
	if why != _toast_text or _clock - _toast_at > 1.5:
		_toast_text = why
		_toast_at = _clock
		hud.toast(why, "info")
		_sound("ui_error", 0.4)
	return false


# ------------------------------------------------------------------- tick --

## Every frame (main.gd's _process): the lesson's conditions, the game's hold, the camera and
## the picture.
func tick(delta: float) -> void:
	if phase == "ended" or steps.is_empty() or step.is_empty():
		return
	_clock += delta
	_refresh_state()
	state["t"] = float(state.get("t", 0.0)) + delta
	match phase:
		"wait":
			if _start_met():
				_activate()
		"active":
			idle_t += delta
			var ready := float(state["t"]) >= MIN_SHOW_S or not bool(state.get("pre", false))
			if ready and Conditions.check(step.get("done", {}), sim, state):
				_complete()
		"done":
			_done_t -= delta
			if _done_t <= 0.0:
				_advance()
	if phase == "ended":
		return
	_update_hold()
	_update_focus(delta)
	_update_ui(delta)


## Called right after the HUD has updated itself (every tenth of a second): the clock's day
## label says what this is.
func after_hud() -> void:
	if phase == "ended" or hud == null:
		return
	hud.day_label.text = "ORIENTATION" if hud.compact else "ORIENTATION DAY"
	hud.apply_lock()


# --------------------------------------------------------------------- UI --

func _update_ui(delta: float) -> void:
	var entries: Array = step.get("wait_anchor" if phase == "wait" else "anchor", [])
	var hit := _resolve(entries)
	target_name = String(hit.name)
	target_rect = hit.rect
	var vp: Vector2 = main._vp()
	spot.view = Rect2(Vector2.ZERO, vp)
	spot.rect = target_rect
	spot.circle = bool(hit.circle)
	spot.pulse = target_rect.size.x > 0.0 and idle_t >= IDLE_PULSE_S and phase == "active"
	spot.arrow = target_rect.size.x > 0.0 and phase == "active" and (arrow_asked or idle_t >= IDLE_ARROW_S)
	spot.reduce_motion = Prefs.on("ui", "reduce_motion")
	spot.avoid = _card_rect
	spot.t += delta
	var next_type := String(step.get("done", {}).get("cond", "")) == "next"
	# (over a page the card is a line and stays one: the button would make it a card that hides the page's first
	# rows, and the ring pulses and the arrow comes by itself anyway)
	show_button.visible = phase == "active" and idle_t >= IDLE_PULSE_S and not next_type and target_rect.size.x > 0.0 and not arrow_asked and not _over_page()
	var dimmed: bool = target_rect.size.x > 0.0 and not bool(hit.world) and bool(step.get("dim", true)) and phase == "active" and not _page_open()
	dim_rect.visible = dimmed
	if dimmed:
		_dim_material.set_shader_parameter("hole", Vector4(target_rect.position.x, target_rect.position.y, target_rect.size.x, target_rect.size.y))
		_dim_material.set_shader_parameter("area", vp)
		_dim_material.set_shader_parameter("strength", DIM)
	_fill_card()
	_place_card(delta, vp)
	spot.queue_redraw()
	hud.apply_lock()


## Writes the card's words when the step, its phase or what it shows changes.
func _fill_card() -> void:
	var line := _page_line() if _page_open() else ""
	var now_goal := _goal_text()
	var key := "%s|%s|%s|%s|%s" % [step_id(), phase, line, skipped, now_goal]
	if key == _card_key:
		return
	_card_key = key
	var is_wrap := phase == "wrap"
	var next_type := String(step.get("done", {}).get("cond", "")) == "next"
	dots.count = steps.size()
	dots.at = index
	dots.queue_redraw()
	skip_button.visible = not is_wrap
	var title := String(step.get("title", ""))
	var text := String(step.get("text", ""))
	var goal := ""
	match phase:
		"wait":
			title = String(step.get("wait_title", title))
			text = String(step.get("wait_text", text))
		"done":
			goal = "Done"
		"active":
			goal = now_goal
			if goal != "":
				goal = goal.substr(0, 1).to_upper() + goal.substr(1)
		"wrap":
			if skipped:
				title = String(step.get("skipped_title", title))
				text = String(step.get("skipped_text", text))
	if line != "":
		title = ""
		text = line
		goal = ""
	title_label.text = title
	title_label.visible = title != ""
	text_label.text = text
	goal_label.text = goal
	goal_label.visible = goal != ""
	goal_label.add_theme_color_override("font_color", hud.OK if phase == "done" else hud.ACCENT)
	next_button.visible = phase == "active" and next_type
	speed_button.visible = phase == "wait"
	wrap_box.visible = is_wrap
	# the wrapped words need a width to know how tall they are: give them the card's, at once
	var inner := CARD_W - card.get_theme_stylebox("panel").get_minimum_size().x
	for l in [title_label, text_label, goal_label]:
		l.custom_minimum_size.x = inner
		l.size.x = inner
	_fade = 0.0
	card.reset_size()


## Whether a page of the HUD is open over the game: the scavenging dialog or the Duty roster. Each has its
## own veil, so the coach adds no dim of its own over it.
func _page_open() -> bool:
	return bool(state.get("dialog", {}).get("open", false)) or bool(state.get("jobs", {}).get("open", false))


## The one line the card says over a page of the HUD: the `line` of the first goal that has one and whose
## moment it is (a lesson whose line changes as it goes: the roster's, a job to give and then Close), else the
## step's `dialog_text`; "" for none (the card keeps its size).
func _page_line() -> String:
	for g in step.get("goals", []):
		if g.has("line") and Conditions.check({"cond": String(g.get("when", "")), "params": g.get("params", {})}, sim, state):
			return String(g.line)
	return String(step.get("dialog_text", ""))


## Whether the card is the short line over a page: one is open, and the step has a line for it.
func _over_page() -> bool:
	return _page_open() and _page_line() != ""


## What the card says to do right now: the first of the step's `goals` whose `when` holds (the
## next part of a step with several), else its `goal` (what the toast says too).
func _goal_text() -> String:
	for g in step.get("goals", []):
		if Conditions.check({"cond": String(g.get("when", "")), "params": g.get("params", {})}, sim, state):
			return String(g.get("text", ""))
	return String(step.get("goal", ""))


## The Speed up button of a card that waits for the day to go by: the fastest speed.
func _speed_up() -> void:
	if main.has_method("_set_speed"):
		main._set_speed(3)
	else:
		main.speed = 3


## Puts the card where it hides nothing: not the lit part, and as little of the HUD as it can.
func _place_card(delta: float, vp: Vector2) -> void:
	card.visible = phase != "ended" and phase != "idle"
	if not card.visible:
		return
	var calm := Prefs.on("ui", "reduce_motion")
	_fade = 1.0 if calm else minf(1.0, _fade + delta * 5.0)
	card.modulate.a = _fade
	var sz := card.get_combined_minimum_size()
	sz.x = maxf(sz.x, CARD_W)
	card.size = sz
	var want := _best_rect(sz, vp, target_rect, _over_page())
	var at := want.position
	_card_rect = Rect2(at, sz)
	if card.position.distance_to(at) > 2.0 and not calm:
		card.position = card.position.lerp(at, minf(1.0, delta * 14.0)) if _fade >= 1.0 else at
	else:
		card.position = at


## The rectangle for a card of size `sz` in a window of size `vp`, in the present step's way
## (see `best_rect`).
func _best_rect(sz: Vector2, vp: Vector2, t: Rect2, compact_top: bool) -> Rect2:
	return best_rect(hud, sz, vp, t, String(step.get("place", "top")), compact_top, phase == "wrap", _kept_clear(), _card_rect)


## What the card keeps off in avatar mode, in screen pixels: the person the player plays (the middle of the screen: the camera
## is on them: the figure, which no card may cover, and the room round it for the gun that a card keeps off if it can) and the gun's
## readout. Nothing without an avatar.
func _kept_clear() -> Array:
	var out: Array = []
	var me = sim.avatar.player() if sim != null else null
	if me == null or me.away != null:
		return out
	var at: Vector2 = main.view_pos(me)
	var a: Vector2 = main._tile_to_screen(at + Vector2(-0.5, -1.9))
	var b: Vector2 = main._tile_to_screen(at + Vector2(0.5, 0.5))
	out.append(Rect2(a, b - a).abs())    # (the figure and its YOU tag: counted twice, with the room round it)
	var c: Vector2 = main._tile_to_screen(at + Vector2(0.0, -0.45))
	var r: float = AVATAR_CLEAR * main.zoom_px
	out.append(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	var gun = hud.get("ammo_panel")
	if gun != null and is_instance_valid(gun) and gun.is_visible_in_tree():
		out.append(gun.get_global_rect())
	return out


## The rectangle for a card of size `sz` in a window of size `vp`: round the target `t` (a rectangle
## on the screen, empty for none) if there is one, else where `place` says ("top" under the crew,
## "center", "bottom"); the one that covers none of the target and least of the HUD's own panels.
## `compact_top` is the small card at the very top (over a page of the HUD). `keep_clear` (avatar mode) is
## more of the screen to keep off, as the target is: the person the player plays and the gun's readout; with
## it a card with no target moves from its place to the nearest where it hides none of them, and `prev` (where the card was) is
## kept unless another place is clearly better (a card that walks about with the person it keeps clear of is no help). Used by the
## hints too.
static func best_rect(hud, sz: Vector2, vp: Vector2, t: Rect2, place: String, compact_top: bool, centered: bool = false, keep_clear: Array = [], prev: Rect2 = Rect2()) -> Rect2:
	var bounds := Rect2(Vector2(EDGE, EDGE), vp - Vector2(EDGE, EDGE) * 2.0)
	var bar: Rect2 = hud.anchor_rect("bar")
	var top_y := bar.end.y + GAP if bar.size.y > 0.0 else 100.0
	var top_center := Rect2(Vector2((vp.x - sz.x) * 0.5, top_y), sz)
	if compact_top:
		return _fit(Rect2(Vector2((vp.x - sz.x) * 0.5, EDGE), sz), bounds)
	var obstacles: Array = []
	for n in ["inspect", "clock", "stores", "bar", "speed", "alerts", "legend", "news.panel", "call", "radio"]:
		var r: Rect2 = hud.anchor_rect(n)
		if r.size.x > 0.0 and not r.intersects(t):
			obstacles.append(r)
	if hud.get("dock") != null and hud.dock.is_visible_in_tree():
		var d: Rect2 = hud.dock.get_global_rect()
		if d.size.x > 0.0 and not d.intersects(t):
			obstacles.append(d)
	if t.size.x <= 0.0 or centered:
		var chosen := top_center
		match place:
			"center":
				chosen = Rect2((vp - sz) * 0.5, sz)
			"bottom":
				chosen = Rect2(Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 110.0), sz)
		if keep_clear.is_empty():
			return _fit(chosen, bounds)
		# its own place first; if that hides the person or the gun's readout, the nearest of the others that does not
		var spots: Array = [chosen, top_center, Rect2(Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 110.0), sz), Rect2(Vector2(EDGE, top_y), sz), Rect2(Vector2(vp.x - sz.x - EDGE, top_y), sz), Rect2(Vector2(EDGE, (vp.y - sz.y) * 0.5), sz), Rect2(Vector2(vp.x - sz.x - EDGE, (vp.y - sz.y) * 0.5), sz), Rect2(Vector2(EDGE, vp.y - sz.y - EDGE), sz), Rect2(Vector2(vp.x - sz.x - EDGE, vp.y - sz.y - EDGE), sz)]
		for k in keep_clear:
			spots.append_array(_beside(k, sz))
		if prev.size == sz:
			spots.append(prev)
		var pick := _fit(chosen, bounds)
		var pick_cost := INF
		for i in spots.size():
			var r := _fit(spots[i], bounds)
			var cost := _hidden(r, keep_clear) * KEEP_WEIGHT + _hidden(r, obstacles) + float(i) * 400.0
			if prev.size == sz and r.position.distance_to(prev.position) < 1.0:
				cost -= STAY_BONUS + float(i) * 400.0
			if cost < pick_cost:
				pick_cost = cost
				pick = r
		return pick
	var avoid := t.grow(10.0)
	var cands: Array = []
	for dx in [0.0, -0.5, -1.0]:
		cands.append(Rect2(Vector2(t.position.x + t.size.x * 0.5 + dx * sz.x, t.end.y + GAP), sz))
		cands.append(Rect2(Vector2(t.position.x + t.size.x * 0.5 + dx * sz.x, t.position.y - GAP - sz.y), sz))
	for dy in [0.0, -0.5, -1.0]:
		cands.append(Rect2(Vector2(t.end.x + GAP, t.position.y + t.size.y * 0.5 + dy * sz.y), sz))
		cands.append(Rect2(Vector2(t.position.x - GAP - sz.x, t.position.y + t.size.y * 0.5 + dy * sz.y), sz))
	cands.append(top_center)
	cands.append(Rect2(Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 110.0), sz))
	cands.append(Rect2(Vector2(EDGE, (vp.y - sz.y) * 0.5), sz))
	cands.append(Rect2(Vector2(vp.x - sz.x - EDGE, (vp.y - sz.y) * 0.5), sz))
	cands.append(Rect2((vp - sz) * 0.5, sz))
	for k in keep_clear:
		cands.append_array(_beside(k, sz))
	if prev.size == sz and not keep_clear.is_empty():
		cands.append(prev)
	var best := top_center
	var best_cost := INF
	var centre := t.get_center()
	for i in cands.size():
		var r := _fit(cands[i], bounds)
		var cost := 0.0
		var hit := r.intersection(avoid)
		cost += hit.size.x * hit.size.y * 50.0
		cost += _hidden(r, keep_clear) * KEEP_WEIGHT
		for o in obstacles:
			var ov: Rect2 = r.intersection(o)
			cost += ov.size.x * ov.size.y
		cost += r.get_center().distance_to(centre) * 20.0 + float(i) * 400.0
		if prev.size == sz and not keep_clear.is_empty() and r.position.distance_to(prev.position) < 1.0:
			cost -= STAY_BONUS + float(i) * 400.0
		if cost < best_cost:
			best_cost = cost
			best = r
	return best


## Places for a card of size `sz` just beside `r`: to its left and right (level with it, a little above and below) and above and
## below it (level, and pushed to either side).
static func _beside(r: Rect2, sz: Vector2) -> Array:
	var c := r.get_center()
	var out: Array = []
	for dy in [0.5, 0.0, 1.0]:
		out.append(Rect2(Vector2(r.position.x - GAP - sz.x, c.y - sz.y * dy), sz))
		out.append(Rect2(Vector2(r.end.x + GAP, c.y - sz.y * dy), sz))
	for dx in [0.5, 0.0, 1.0]:
		out.append(Rect2(Vector2(c.x - sz.x * dx, r.position.y - GAP - sz.y), sz))
		out.append(Rect2(Vector2(c.x - sz.x * dx, r.end.y + GAP), sz))
	return out


## The area of `r` that lies over any of the rectangles.
static func _hidden(r: Rect2, over: Array) -> float:
	var area := 0.0
	for o in over:
		var ov: Rect2 = r.intersection(o)
		area += ov.size.x * ov.size.y
	return area


## `r` moved to lie inside `bounds` (as much as it can).
static func _fit(r: Rect2, bounds: Rect2) -> Rect2:
	var p := r.position
	p.x = clampf(p.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - r.size.x))
	p.y = clampf(p.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - r.size.y))
	return Rect2(p, r.size)


## Any click or key the player makes counts as being there (and Enter reads a card).
func _input(ev: InputEvent) -> void:
	if phase == "ended":
		return
	if ev is InputEventMouseButton and ev.pressed or ev is InputEventKey and ev.pressed and not ev.echo:
		idle_t = 0.0
		if ev is InputEventKey and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER) and phase == "active" and hud.scavenge_dialog == null:
			if String(step.get("done", {}).get("cond", "")) == "next":
				press_next()
				get_viewport().set_input_as_handled()
