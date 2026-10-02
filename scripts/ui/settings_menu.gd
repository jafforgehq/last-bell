## Settings: five volumes (master, effects, ambience, music, interface), the size of the interface
## (80% to 150%), hints, reduce motion and fullscreen (not on the web). Every change applies
## at once and is kept at once (`Prefs`, scripts/prefs.gd); the game reads them again when it
## starts. Used from the title and from the pause menu.
extends "res://scripts/ui/menu_screen.gd"

const Prefs := preload("res://scripts/prefs.gd")
const Buses := preload("res://scripts/audio/buses.gd")

## The volume rows: [pref key, what the player reads, the audio bus].
const VOLUMES := [["master", "Master", "Master"], ["sfx", "Effects", "SFX"], ["ambience", "Ambience", "Ambience"], ["music", "Music", "Music"], ["ui", "Interface", "UI"]]
const SCALE_MIN := 0.8
const SCALE_MAX := 1.5
const SCALE_STEP := 0.1
## The switches: [pref key, what the player reads, and what it does].
const SWITCHES := [
	["hints", "Hints", "Tips and reminders while you play"],
	["reduce_motion", "Reduce motion", "Keeps the screen still: no camera drift, no fades"],
	["fullscreen", "Fullscreen", "Fills the whole screen"],
]

## In a window shorter than this the rows sit closer together, so that the whole screen fits the
## smallest window (700 by 560) without scrolling.
const COMPACT_H := 640.0

## The sliders and their percent labels, by pref key.
var sliders := {}
var percents := {}
var scale_minus: Button
var scale_plus: Button
var scale_value: Label
var scale_note: Label
## The switch buttons by pref key (fullscreen is missing on the web).
var toggles := {}
var back_button: Button
var _dragging := false
var _last_preview := 0


func _init() -> void:
	kind = "settings"
	max_w = 580.0


## Fullscreen on or off, as the setting says (not on the web, where the page decides, and not
## in a headless run).
static func apply_fullscreen() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var want := Prefs.on("ui", "fullscreen")
	if want and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _build_body() -> void:
	body.add_child(section("Sound"))
	for v in VOLUMES:
		body.add_child(_volume_row(String(v[0]), String(v[1]), String(v[2])))
	body.add_child(line())
	body.add_child(section("Screen"))
	body.add_child(_scale_row())
	scale_note = note("This window is too small for a bigger interface.", hud.WARN, 13)
	scale_note.visible = false
	body.add_child(scale_note)
	for sw in SWITCHES:
		if String(sw[0]) == "fullscreen" and shell.on_web():
			continue
		body.add_child(_switch_row(String(sw[0]), String(sw[1]), String(sw[2])))
	_refresh_scale()


func _build_foot() -> void:
	back_button = button("Back", true)
	back_button.pressed.connect(close)
	foot.add_child(back_button)


func default_focus() -> Control:
	return sliders.get("master", back_button)


func _layout() -> void:
	body.add_theme_constant_override("separation", 10 if size.y >= COMPACT_H else 2)
	super._layout()


# -------------------------------------------------------------- volumes --

func _volume_row(key: String, label_text: String, bus: String) -> Control:
	# a slider draws no ring of its own when the keyboard is on it: the whole row does
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", _ring_box(false))
	var row: HBoxContainer = hud._hbox(12)
	ring.add_child(row)
	var l: Label = hud._label(label_text, Fonts.sans(500), 15, ink())
	l.custom_minimum_size.x = 112
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = Buses.volume_of(bus)
	s.scrollable = false
	s.focus_mode = Control.FOCUS_ALL
	s.custom_minimum_size = Vector2(140, 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(s)
	s.value_changed.connect(_on_volume.bind(key, bus))
	s.drag_started.connect(func(): _dragging = true)
	s.drag_ended.connect(func(_moved): _dragging = false; _preview(key))
	row.add_child(s)
	var p: Label = hud._label(Kit.percent_text(s.value), Fonts.cond(600), 15, ink2())
	p.custom_minimum_size.x = 48
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(p)
	sliders[key] = s
	percents[key] = p
	s.focus_entered.connect(func(): ring.add_theme_stylebox_override("panel", _ring_box(true)))
	s.focus_exited.connect(func(): ring.add_theme_stylebox_override("panel", _ring_box(false)))
	return ring


## The box round a row: gold while the keyboard is on it, clear (but as thick, so nothing moves) when not.
func _ring_box(on: bool) -> StyleBoxFlat:
	var b := Kit.focus_box(hud.ACCENT if on else Color(0, 0, 0, 0), 6)
	b.expand_margin_left = 0
	b.expand_margin_right = 0
	b.expand_margin_top = 0
	b.expand_margin_bottom = 0
	b.content_margin_left = 6
	b.content_margin_right = 6
	b.content_margin_top = 2
	b.content_margin_bottom = 2
	return b


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.16)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = hud.ACCENT
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = hud.ACCENT.lightened(0.18)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", Kit.disc(9, hud.INK, hud.ACCENT, 3.0))
	s.add_theme_icon_override("grabber_highlight", Kit.disc(10, hud.INK, hud.ACCENT.lightened(0.18), 3.0))


func _on_volume(v: float, key: String, bus: String) -> void:
	var value := snappedf(clampf(v, 0.0, 1.0), 0.05)
	Prefs.set_value("audio", key, value)
	Buses.apply(bus)
	percents[key].text = Kit.percent_text(value)
	if not _dragging:
		_preview(key)


## A sound at the new volume, so that the ear can judge it (not too often).
func _preview(key: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_preview < 140:
		return
	_last_preview = now
	match key:
		"sfx":
			var s = shell.main.get("sound") if shell.main != null else null
			if s != null and s.has_method("play"):
				s.play("thud", 0.8, 0.0)
		"master", "ui":
			shell.play("ui_click")


# ---------------------------------------------------------- interface size --

func _scale_row() -> Control:
	var row: HBoxContainer = hud._hbox(8)
	var l: Label = hud._label("Interface size", Fonts.sans(500), 15, ink())
	l.custom_minimum_size.x = 112
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	scale_minus = button("−", false)
	scale_minus.custom_minimum_size = Vector2(44, 38)
	scale_minus.pressed.connect(_step_scale.bind(-1))
	row.add_child(scale_minus)
	scale_value = hud._label("100%", Fonts.cond(700), 17, ink())
	scale_value.custom_minimum_size.x = 60
	scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(scale_value)
	scale_plus = button("+", false)
	scale_plus.custom_minimum_size = Vector2(44, 38)
	scale_plus.pressed.connect(_step_scale.bind(1))
	row.add_child(scale_plus)
	return row


func _step_scale(direction: int) -> void:
	var v := snappedf(clampf(Prefs.number("ui", "scale") + SCALE_STEP * direction, SCALE_MIN, SCALE_MAX), 0.05)
	Prefs.set_value("ui", "scale", v)
	_changed()
	_refresh_scale()
	# a button that has just gone dark cannot keep the keyboard
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused is Button and focused.disabled:
		(scale_plus if focused == scale_minus else scale_minus).grab_focus()


func _refresh_scale() -> void:
	var v := Prefs.number("ui", "scale")
	scale_value.text = Kit.percent_text(v)
	scale_minus.disabled = v <= SCALE_MIN + 0.001
	scale_plus.disabled = v >= SCALE_MAX - 0.001
	# the window may be too small to give the size that was asked for
	var shown: float = shell.main.ui_scale_in_use() if shell.main != null and shell.main.has_method("ui_scale_in_use") else v
	scale_note.visible = shown < v - 0.01


# ------------------------------------------------------------- switches --

func _switch_row(key: String, label_text: String, detail: String) -> Control:
	var row: HBoxContainer = hud._hbox(12)
	var col: VBoxContainer = hud._vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(hud._label(label_text, Fonts.sans(500), 15, ink()))
	var d := note(detail, ink3(), 13)
	d.custom_minimum_size.x = 120
	col.add_child(d)
	row.add_child(col)
	var b := button("", false)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(84, 38)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = detail
	b.set_pressed_no_signal(Prefs.on("ui", key))
	_paint_switch(b)
	b.toggled.connect(_on_switch.bind(key, b))
	row.add_child(b)
	toggles[key] = b
	return row


func _paint_switch(b: Button) -> void:
	b.text = "On" if b.button_pressed else "Off"
	shell.restyle(b, b.button_pressed)


func _on_switch(on: bool, key: String, b: Button) -> void:
	Prefs.set_value("ui", key, on)
	_paint_switch(b)
	_changed()


## Tells the game to read the settings again (the size, the hints, fullscreen, the volumes).
func _changed() -> void:
	if shell.main != null and shell.main.has_method("apply_settings"):
		shell.main.apply_settings()
	else:
		Buses.apply_all()
		apply_fullscreen()
	shell.on_settings_changed()
