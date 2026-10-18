## The one look of the prison game's windows (the Base screen, the radio and morning cards, the loadout, the orders panel, the map of places, the story log, the pause
## menu and the endings): the chalkboard in oak trim of the title and New game screens as the frame, a gold title, the same type sizes, the menus' framed buttons, and
## the motion they share (a short fade and slide in, a fade out, a press that sinks a pixel, the click, numbers that count to their new value).
##
##     const UI := preload("res://scripts/prison/prison_ui.gd")
##     panel.add_theme_stylebox_override("panel", UI.frame_box(14))
##     var b := UI.button("Close (Esc)")       # framed, with hover, press and the click
##     UI.open_fx(panel)                        # after it is shown
##     UI.close_fx(panel)                       # before it is hidden
##
## Motion never holds anything up: a window is open (and takes input) the frame it is shown, and gone the frame it is closed (what fades out is a copy that takes no
## mouse). With no display (the tests) there is no motion at all and the counters show their value at once.
extends RefCounted

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The type sizes every window uses: its title, a heading inside it, the running text, the small print, and the words on a button.
const TITLE_PX := 24
const HEAD_PX := 18
const BODY_PX := 15
const SMALL_PX := 13
const BUTTON_PX := 16
## The cards (a radio message, a letter, a morning event, the morning summary): a bigger title and the story's prose a little bigger than a window's text.
const CARD_TITLE_PX := 34
const PROSE_PX := 18
## The motion: the fade and slide in, the fade out, how far it slides, how long a number takes to count to its new value.
const OPEN_S := 0.15
const CLOSE_S := 0.12
const SLIDE_PX := 12.0
const TICK_S := 0.3
## How much a pressed button darkens.
const PRESS_DARK := Color(0.8, 0.8, 0.8)

static var _ticks := {}    # key -> {from, to, t0}: the counters that count


## Whether there is anything to see move (no display in the tests: no motion).
static func motion() -> bool:
	return DisplayServer.get_name() != "headless"


# ------------------------------------------------------------------------------------- the look --

## The window's frame: the chalkboard in oak trim (flat dark slate with a thin line when the picture is missing), `margin` px of room inside it.
static func frame_box(margin: int = 14) -> StyleBox:
	var f: StyleBox = Hud.frame("panel")
	if f == null:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(Hud.PANEL, 0.985)
		s.border_color = Hud.LINE2
		s.set_border_width_all(1)
		s.set_corner_radius_all(6)
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = 12
		f = s
	f.set_content_margin_all(margin)
	return f


## A window's title (gold, condensed, TITLE_PX unless told).
static func title(text: String, px: int = TITLE_PX, col: Color = Hud.ACCENT) -> Label:
	return label(text, px, col, true)


## A label in the windows' fonts: condensed bold for a heading, the sans for text.
static func label(text: String, px: int = BODY_PX, col: Color = Hud.INK, cond := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.cond(700) if cond else Fonts.sans(500))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A framed button of the windows (`primary`: the gold main choice). It takes no keyboard focus: the keys stay the game's.
static func button(text: String, primary := false, px: int = BUTTON_PX) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Fonts.cond(700))
	b.add_theme_font_size_override("font_size", px)
	skin(b, primary)
	return b


## Puts the framed look on a button (normal, hover, pressed, disabled; a toggle's pressed state is its "on" look) and the press feedback.
static func skin(b: Button, primary := false) -> void:
	var kinds: Array = ["button_primary", "button_primary_hover", "button_primary_pressed", "button_off"] if primary else ["button", "button_hover", "button_pressed", "button_off"]
	var states := ["normal", "hover", "pressed", "disabled"]
	for i in 4:
		var s := _button_box(String(kinds[i]), String(states[i]), primary)
		if states[i] == "pressed":
			_darken(s)
		b.add_theme_stylebox_override(String(states[i]), s)
	b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Hud.ACCENT_INK if primary else Hud.INK
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink if primary else Hud.ACCENT)
	b.add_theme_color_override("font_pressed_color", ink if primary else Hud.ACCENT)
	b.add_theme_color_override("font_hover_pressed_color", ink if primary else Hud.ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(ink, 0.5) if not primary else Color(Hud.ACCENT_INK, 0.6))
	feedback(b)


static func _button_box(kind: String, state: String, primary: bool) -> StyleBox:
	var s: StyleBox = Hud.frame(kind)
	if s == null:
		var f := StyleBoxFlat.new()
		f.set_corner_radius_all(5)
		f.set_border_width_all(1)
		f.bg_color = Hud.ACCENT if primary else Color(Hud.PANEL_HI, 0.95)
		f.border_color = Hud.ACCENT if primary or state == "hover" else Hud.LINE2
		if state == "hover":
			f.bg_color = Hud.ACCENT.lightened(0.14) if primary else Color(0.26, 0.34, 0.3, 0.96)
		elif state == "disabled":
			f.bg_color = Color(f.bg_color, 0.4)
		s = f
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func _darken(s: StyleBox) -> void:
	if s is StyleBoxTexture:
		(s as StyleBoxTexture).modulate_color = (s as StyleBoxTexture).modulate_color * PRESS_DARK
	elif s is StyleBoxFlat:
		(s as StyleBoxFlat).bg_color = (s as StyleBoxFlat).bg_color.darkened(0.2)


## The press of any button (also one with its own look): it sinks a pixel and darkens while held, and clicks when it fires. Visual only: the layout does not move.
static func feedback(b: BaseButton) -> void:
	if b.has_meta("ui_fb"):
		return
	b.set_meta("ui_fb", true)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.offset_transform_enabled = true
	b.button_down.connect(func():
		b.offset_transform_position = Vector2(0, 1)
		b.self_modulate = PRESS_DARK)
	var up := func():
		b.offset_transform_position = Vector2.ZERO
		b.self_modulate = Color.WHITE
	b.button_up.connect(up)
	b.mouse_exited.connect(up)
	b.pressed.connect(func(): click(b))


## The menus' click (the game's sound, found up the tree), quietly.
static func click(from: Node) -> void:
	var n := from
	while n != null:
		var s = n.get("sound")
		if s != null and s is Object and (s as Object).has_method("ui"):
			s.ui("ui_click", 0.5)
			return
		n = n.get_parent()


## Every button under `root` gets the press feedback (for a page built of plain buttons).
static func feedback_all(root: Node) -> void:
	if root is BaseButton:
		feedback(root)
	for c in root.get_children():
		feedback_all(c)


# ----------------------------------------------------------------------------------- the motion --

## A window just shown fades in and slides up into place (visual only: it is where it is, and takes input, at once).
static func open_fx(c: Control) -> void:
	if c == null or not motion() or not c.is_inside_tree():
		return
	if c.has_meta("ui_tw"):
		var old = c.get_meta("ui_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	c.offset_transform_enabled = true
	c.offset_transform_position = Vector2(0, SLIDE_PX)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "modulate:a", 1.0, OPEN_S)
	tw.tween_property(c, "offset_transform_position", Vector2.ZERO, OPEN_S)
	c.set_meta("ui_tw", tw)


## A window about to be hidden leaves a copy of itself that fades out (it takes no mouse and holds nothing up). Call it before hiding the window.
static func close_fx(c: Control) -> void:
	if c == null or not motion() or not c.is_inside_tree() or not c.is_visible_in_tree():
		return
	var g := c.duplicate(0) as Control    # (no scripts or signals: a picture of the window, not a second one)
	if g == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = _layer_of(c)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	c.get_tree().root.add_child(layer)
	layer.add_child(g)
	g.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g.visible = true
	g.position = c.get_global_rect().position
	g.size = c.size
	g.offset_transform_position = Vector2.ZERO
	g.modulate.a = c.modulate.a
	_no_mouse(g)
	var tw := g.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(g, "modulate:a", 0.0, CLOSE_S)
	tw.tween_callback(layer.queue_free)


static func _layer_of(n: Node) -> int:
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 1


static func _no_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_no_mouse(c)


# --------------------------------------------------------------------------------- the counters --

## The value a counter shows: when `value` (named `key`) changes, the shown value counts to it over TICK_S, eased out. At once with no display or on the first call.
static func tick(key: String, value: float) -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var e = _ticks.get(key)
	if e == null or not motion():
		_ticks[key] = {"from": value, "to": value, "t0": -100.0}
		return value
	if not is_equal_approx(float(e.to), value):
		e.from = _shown(e, now)
		e.to = value
		e.t0 = now
	return _shown(e, now)


## Whether a counter is still counting (its owner then redraws it every frame).
static func ticking() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for k in _ticks:
		if now - float(_ticks[k].t0) < TICK_S:
			return true
	return false


static func _shown(e: Dictionary, now: float) -> float:
	var k := clampf((now - float(e.t0)) / TICK_S, 0.0, 1.0)
	k = 1.0 - (1.0 - k) * (1.0 - k)
	return lerpf(float(e.from), float(e.to), k)
