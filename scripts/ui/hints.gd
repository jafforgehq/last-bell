## Tips for a normal run: the first time something happens that the game has not explained (the
## first dusk, the first stock that runs low, the first wound, a fever, a fallen wall, runners, a
## brute) a small card says what it means and what to do, once. It is the coach's card and ring
## (scripts/ui/coach.gd) on the conditions of scripts/tutorial_conditions.gd, with the lessons
## replaced by assets/data/hints.json and none of the teaching: it never holds the game, never
## locks an order and never hides a menu.
##
## - A tip comes when its `start` condition first holds and `Prefs.flag("hint_<id>")` is not set; the
##   flag is set the moment it is shown, so it comes once, ever. It stays until Got it or 25 seconds.
## - One at a time, and not more often than every 45 seconds. Not in the first 20 seconds of a run,
##   not in the tutorial, not under a menu, the scavenging dialog or the game-over screen.
## - Settings can turn them off (`Prefs.on("ui", "hints")`), and so can the card ("Turn tips off").
## - Not in a headless run (the tests and the harness): they would write the player's own flags. A
##   test arms them by hand (`armed = true`) after pointing Prefs at a file of its own.
extends CanvasLayer

const Fonts := preload("res://scripts/ui/fonts.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Prefs := preload("res://scripts/prefs.gd")

const HINTS_PATH := "res://assets/data/hints.json"
const CARD_W := 320.0
## Sim seconds into a run before the first tip, real seconds between tips, how long one stays, and
## how often the conditions are looked at.
const FIRST_AFTER_S := 20.0
const GAP_S := 45.0
const STAY_S := 25.0
const LOOK_EVERY_S := 1.0

var main
var hud
var sim
var hints: Array = []
## Whether tips may come at all: not in a headless run unless a test says so.
var armed := true
## The tip on show ({} for none), how long it still has, and the wait before the next may come.
var active := {}
var left_s := 0.0
var quiet_s := 0.0

var card: PanelContainer
var title_label: Label
var text_label: Label
var ok_button: Button
var off_button: Button
var spot: Coach.Spot
var target_rect := Rect2()
var _look_s := 0.0
var _clock := 0.0
var _fade := 0.0


## The tips of the file (an empty list, and an error, when it cannot be read).
static func load_hints(path: String = HINTS_PATH) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("hints")) != TYPE_ARRAY:
		push_error("Could not read the tips from %s" % path)
		return []
	return parsed.hints


func setup(game, game_hud, game_sim, all_hints: Array) -> void:
	main = game
	hud = game_hud
	sim = game_sim
	hints = all_hints
	armed = DisplayServer.get_name() != "headless"
	layer = 4
	name = "Hints"
	spot = Coach.Spot.new()
	spot.name = "Spot"
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spot.ring = hud.ACCENT
	add_child(spot)
	card = hud._panel()
	card.name = "Card"
	card.custom_minimum_size.x = CARD_W
	card.visible = false
	var col: VBoxContainer = hud._vbox(8)
	title_label = hud._label("", Fonts.cond(700), 20, hud.INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title_label)
	text_label = hud._label("", Fonts.sans(400), 15, hud.INK)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text_label)
	var row: HBoxContainer = hud._hbox(8)
	off_button = Button.new()
	off_button.text = "Turn tips off"
	off_button.flat = true
	off_button.focus_mode = Control.FOCUS_NONE
	off_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	off_button.add_theme_font_override("font", Fonts.sans(600))
	off_button.add_theme_font_size_override("font_size", 13)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		off_button.add_theme_color_override(key, hud.INK3 if key == "font_color" else hud.INK)
	off_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	off_button.pressed.connect(turn_off)
	row.add_child(off_button)
	row.add_child(hud._spacer())
	ok_button = hud._button("Got it", true)
	ok_button.custom_minimum_size = Vector2(96, 36)
	ok_button.pressed.connect(dismiss)
	row.add_child(ok_button)
	col.add_child(row)
	card.add_child(col)
	add_child(card)


## Whether a tip may be on the screen now.
func can_show() -> bool:
	if not armed or not Prefs.on("ui", "hints"):
		return false
	if main.get("coach") != null or bool(main.get("tutorial")) or bool(main.get("title_mode")):
		return false
	if bool(main.get("menu_open")) or hud.scavenge_dialog != null or hud.game_over != null:
		return false
	return sim.over == ""


## The id of the tip on show, or "".
func shown_id() -> String:
	return String(active.get("id", ""))


## Every frame (main.gd's _process).
func tick(delta: float) -> void:
	_clock += delta
	if not can_show():
		_hide()
		return
	quiet_s = maxf(0.0, quiet_s - delta)
	if active.is_empty():
		_look_s -= delta
		if _look_s <= 0.0:
			_look_s = LOOK_EVERY_S
			if quiet_s <= 0.0 and sim.t >= FIRST_AFTER_S:
				var found := _next_tip()
				if not found.is_empty():
					_show(found)
	else:
		left_s -= delta
		if left_s <= 0.0:
			dismiss()
	_update_ui(delta)


## The first tip whose moment has come and that has not been shown.
func _next_tip() -> Dictionary:
	for h in hints:
		if Prefs.flag("hint_%s" % String(h.id)):
			continue
		if Conditions.check(h.get("start", {}), sim, {}):
			return h
	return {}


func _show(h: Dictionary) -> void:
	Prefs.set_flag("hint_%s" % String(h.id))
	active = h
	left_s = STAY_S
	title_label.text = String(h.get("title", ""))
	text_label.text = String(h.get("text", ""))
	var inner := CARD_W - card.get_theme_stylebox("panel").get_minimum_size().x
	for l in [title_label, text_label]:
		l.custom_minimum_size.x = inner
		l.size.x = inner
	card.reset_size()
	_fade = 0.0
	var player = main.get("sound")
	if player != null and is_instance_valid(player) and player.has_method("ui"):
		player.ui("ui_open", 0.4)


## Got it, or the time is up: the tip goes and the next waits its turn.
func dismiss() -> void:
	active = {}
	quiet_s = GAP_S
	_hide()


## "Turn tips off": the setting goes off for good (it can come back in the settings).
func turn_off() -> void:
	Prefs.set_value("ui", "hints", false)
	dismiss()


func _hide() -> void:
	if card != null:
		card.visible = false
	if spot != null:
		spot.rect = Rect2()
		spot.queue_redraw()


func _update_ui(delta: float) -> void:
	if active.is_empty():
		_hide()
		return
	var vp: Vector2 = main._vp()
	var calm := Prefs.on("ui", "reduce_motion")
	target_rect = Rect2()
	for anchor_name in active.get("anchor", []):
		var r: Rect2 = hud.anchor_rect(String(anchor_name))
		if r.size.x > 0.0 and r.size.y > 0.0:
			target_rect = r
			break
	spot.view = Rect2(Vector2.ZERO, vp)
	spot.rect = target_rect
	spot.circle = false
	spot.pulse = false
	spot.arrow = false
	spot.reduce_motion = calm
	spot.t += delta
	spot.queue_redraw()
	card.visible = true
	_fade = 1.0 if calm else minf(1.0, _fade + delta * 5.0)
	card.modulate.a = _fade
	var sz := card.get_combined_minimum_size()
	sz.x = maxf(sz.x, CARD_W)
	card.size = sz
	card.position = _place(sz, vp)


## Under the stores, at the left (where it is out of the way of the wall and the crew); at the top
## under the crew when the window has no room there.
func _place(sz: Vector2, vp: Vector2) -> Vector2:
	var left = hud.get("left_col")
	var at := Vector2(Coach.EDGE, 100.0)
	if left != null and is_instance_valid(left) and left.is_visible_in_tree():
		at = Vector2(Coach.EDGE, left.get_global_rect().end.y + Coach.GAP)
	var mine := Rect2(at, sz)
	var bounds := Rect2(Vector2.ZERO, vp).grow(-Coach.EDGE)
	var blocked := not bounds.encloses(mine)
	for n in ["inspect", "speed", "clock", "bar"]:
		var r: Rect2 = hud.anchor_rect(n)
		if r.size.x > 0.0 and r.intersects(mine):
			blocked = true
	if hud.get("dock") != null and hud.dock.is_visible_in_tree() and hud.dock.get_global_rect().intersects(mine):
		blocked = true
	if blocked:
		return Coach.best_rect(hud, sz, vp, Rect2(), "top", false).position
	return at
