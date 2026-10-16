## Settings: five volumes (master, effects, ambience, music, interface), the size of the interface
## (80% to 150%), hints, reduce motion and fullscreen (not on the web), and how the mouse aims (round 22:
## "Right button aims" or "Always aim at the mouse", scripts/aim_mode.gd). Every change applies
## at once and is kept at once (`Prefs`, scripts/prefs.gd); the game reads them again when it
## starts. Used from the title and from the pause menu.
extends "res://scripts/ui/menu_screen.gd"

const Prefs := preload("res://scripts/prefs.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const SettingsExtras := preload("res://scripts/ui/settings_extras.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const HudStage := preload("res://scripts/ui/hud_stage.gd")

## The volume rows: [pref key, what the player reads, the audio bus].
const VOLUMES := [["master", "Master", "Master"], ["sfx", "Effects", "SFX"], ["ambience", "Ambience", "Ambience"], ["music", "Music", "Music"], ["ui", "Interface", "UI"]]
const SCALE_MIN := 0.8
const SCALE_MAX := 1.5
const SCALE_STEP := 0.1
## The Brightness slider's reach (scripts/render/dark_look.gd has the same).
const BRIGHT_MIN := 0.7
const BRIGHT_MAX := 1.3
## The switches: [pref key, what the player reads, and what it does].
const SWITCHES := [
	["hints", "Hints", "Tips and reminders while you play"],
	["reduce_motion", "Reduce motion", "Keeps the screen still: no camera drift, no fades, no pulsing"],
	["minimap", "Minimap", "A small map of the streets round you, in a corner"],
	["fullscreen", "Fullscreen", "Fills the whole screen (F11 does it from anywhere)"],
]

## In a window shorter than this the rows sit closer together and their buttons are a little slimmer, so that the whole screen fits the
## smallest window (700 by 560) without scrolling.
const COMPACT_H := 640.0
const SPACIOUS_H := 1000.0
const ROW_H_MID := 34.0
## How tall the buttons of the rows are (the size, the switches, the aiming), and in a short window.
const ROW_H := 38.0
## (the dark look's Brightness row took 25 px of the smallest window: its buttons are 4 px slimmer, nine of them)
const ROW_H_COMPACT := 28.0
## (HUD8: the HUD row is one more row, and the smallest window (700 by 560) has the buttons of the rows four pixels slimmer again)
const ROW_H_SMALLEST := 24.0
## In a window shorter than this the switches sit two to a row and lose their second line (it is their tooltip too), and the aiming's note goes, so that the page fits the small
## windows (700 by 560, 1024 by 640) without a scroll: the Accessibility and Brightness rows made it 540 px tall.
const GRID_H := 720.0

## The sliders and their percent labels, by pref key.
var sliders := {}
## The grids the switches are in (one column, or two in a short window) and the second lines of the switches.
var _grids: Array = []
var _notes: Array = []
var percents := {}
var scale_minus: Button
var scale_plus: Button
var scale_value: Label
var scale_note: Label
## The switch buttons by pref key (fullscreen is missing on the web).
var toggles := {}
## The two ways to aim (AimMode.RIGHT, AimMode.ALWAYS) as buttons, and the line that says what the one chosen does.
var aim_buttons := {}
## HUD8: the two HUD modes as buttons ("minimal", "full": scripts/ui/hud_stage.gd) and the line that says what the one chosen does.
var hud_buttons := {}
var hud_note: Label
## The three "Text size" buttons by size ("normal", "large", "larger"; scripts/ui/settings_extras.gd).
var text_buttons := {}
var aim_note: Label
var back_button: Button
var _dragging := false
var _last_preview := 0


func _init() -> void:
	kind = "settings"
	max_w = 580.0


## What the setting was when the window was last put in or out of fullscreen (null: not yet, this process). The setting is applied when it CHANGES (and at the start), so
## that a window the player took in or out of fullscreen with the system's own button is not put back by an unrelated setting (a volume).
static var _fullscreen_applied = null


## Whether the window fills the screen now.
static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Fullscreen on or off, as the setting says (not on the web, where the page decides, and not
## in a headless run).
static func apply_fullscreen() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var want := Prefs.on("ui", "fullscreen")
	if _fullscreen_applied != null and bool(_fullscreen_applied) == want:
		return
	_fullscreen_applied = want
	var is_full := is_fullscreen()
	if want and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## F11: the window goes in or out of fullscreen whatever the setting says now, and the setting follows (it is kept for the next start). False when this
## cannot be done (a browser has its own F11; a headless run has no window).
static func toggle_fullscreen() -> bool:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return false
	Prefs.set_value("ui", "fullscreen", not is_fullscreen())
	_fullscreen_applied = null
	apply_fullscreen()
	return true


## The switches show the settings as they are now (F11 changed one while this screen was up).
func sync_switches() -> void:
	for key in toggles:
		var b: Button = toggles[key]
		b.set_pressed_no_signal(Prefs.on("ui", String(key)))
		_paint_switch(b)


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
	body.add_child(_brightness_row())
	var grid := new_switch_grid()
	for sw in SWITCHES:
		if String(sw[0]) == "fullscreen" and shell.on_web():
			continue
		grid.add_child(_switch_row(String(sw[0]), String(sw[1]), String(sw[2])))
	body.add_child(grid)
	body.add_child(_hud_row())
	body.add_child(section("Controls"))
	body.add_child(_aim_row())
	aim_note = note("", ink3(), 13)
	body.add_child(aim_note)
	SettingsExtras.add_rows(self)    # (Accessibility: text size, colour-blind markers, reduce flashes)
	_refresh_aim()
	_refresh_hud()
	_refresh_scale()


func _build_foot() -> void:
	back_button = button("Back", true)
	back_button.pressed.connect(close)
	foot.add_child(back_button)


func default_focus() -> Control:
	return sliders.get("master", back_button)


func _layout() -> void:
	# (three sizes: roomy from SPACIOUS_H up; between that and COMPACT_H a little closer, so that the Accessibility rows fit a 1280 by 800 window without scrolling; the smallest as before)
	var gap := 10 if size.y >= SPACIOUS_H else (4 if size.y >= COMPACT_H else 1)
	body.add_theme_constant_override("separation", gap)
	var tight := size.y < GRID_H
	for g in _grids:
		g.columns = 2 if tight else 1
		g.add_theme_constant_override("v_separation", gap)
	for n in _notes:
		n.visible = not tight
	if aim_note != null:
		aim_note.visible = not tight
	_fit_rows(ROW_H if size.y >= SPACIOUS_H else (ROW_H_MID if size.y >= COMPACT_H and not tight else (ROW_H_COMPACT if size.y >= COMPACT_H else ROW_H_SMALLEST)))
	super._layout()


## The buttons of the rows are `h` tall (round 22's Controls section made the screen 12 px too tall for the smallest window).
func _fit_rows(h: float) -> void:
	var buttons: Array = [scale_minus, scale_plus]
	buttons.append_array(toggles.values())
	buttons.append_array(aim_buttons.values())
	buttons.append_array(hud_buttons.values())
	buttons.append_array(text_buttons.values())
	for b in buttons:
		if b != null and not is_equal_approx(b.custom_minimum_size.y, h):
			b.custom_minimum_size.y = h


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
	s.custom_minimum_size = Vector2(140, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(s)
	s.tooltip_text = String(SettingsExtras.VOLUME_TIPS.get(key, ""))
	ring.tooltip_text = s.tooltip_text
	ring.mouse_filter = Control.MOUSE_FILTER_PASS    # (the label and the number have a tooltip too: the row's)
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
	b.content_margin_top = 1
	b.content_margin_bottom = 1
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


# -------------------------------------------------------------- brightness --

## "Brightness": the game is dark on purpose (an overcast day, a night that is really dark); this lifts or lowers the whole picture, 70% to 130%, 100% as it is made
## (scripts/render/dark_look.gd reads `ui.brightness` and puts it in the last pass of the grade; the interface is not touched by it).
func _brightness_row() -> Control:
	var ring := PanelContainer.new()
	ring.add_theme_stylebox_override("panel", _ring_box(false))
	var row: HBoxContainer = hud._hbox(12)
	ring.add_child(row)
	var l: Label = hud._label("Brightness", Fonts.sans(500), 15, ink())
	l.custom_minimum_size.x = 112
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = BRIGHT_MIN
	s.max_value = BRIGHT_MAX
	s.step = 0.05
	s.value = clampf(Prefs.number("ui", "brightness"), BRIGHT_MIN, BRIGHT_MAX)
	s.scrollable = false
	s.focus_mode = Control.FOCUS_ALL
	s.custom_minimum_size = Vector2(140, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(s)
	s.tooltip_text = "The game is dark on purpose. Raise this if your screen is dim, or lower it for a grimmer look. The interface does not change."
	ring.tooltip_text = s.tooltip_text
	ring.mouse_filter = Control.MOUSE_FILTER_PASS
	s.value_changed.connect(_on_brightness)
	row.add_child(s)
	var p: Label = hud._label(Kit.percent_text(s.value), Fonts.cond(600), 15, ink2())
	p.custom_minimum_size.x = 48
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(p)
	sliders["brightness"] = s
	percents["brightness"] = p
	s.focus_entered.connect(func(): ring.add_theme_stylebox_override("panel", _ring_box(true)))
	s.focus_exited.connect(func(): ring.add_theme_stylebox_override("panel", _ring_box(false)))
	return ring


func _on_brightness(v: float) -> void:
	var value := snappedf(clampf(v, BRIGHT_MIN, BRIGHT_MAX), 0.05)
	Prefs.set_value("ui", "brightness", value)
	percents["brightness"].text = Kit.percent_text(value)
	_changed()


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
	scale_minus.tooltip_text = String(SettingsExtras.SCALE_TIPS.minus)
	scale_minus.pressed.connect(_step_scale.bind(-1))
	row.add_child(scale_minus)
	scale_value = hud._label("100%", Fonts.cond(700), 17, ink())
	scale_value.custom_minimum_size.x = 60
	scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(scale_value)
	scale_plus = button("+", false)
	scale_plus.custom_minimum_size = Vector2(44, 38)
	scale_plus.tooltip_text = String(SettingsExtras.SCALE_TIPS.plus)
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
	# (100% is the size that fits this screen: a big window has made it bigger already, `Main.auto_ui_scale`; the setting is on top of that)
	var shown: float = shell.main.ui_scale_in_use() if shell.main != null and shell.main.has_method("ui_scale_in_use") else v
	if shell.main != null and shell.main.has_method("ui_auto_scale"):
		shown /= maxf(0.01, float(shell.main.ui_auto_scale()))
	scale_note.visible = shown < v - 0.01


# ------------------------------------------------------------- switches --

## The grid the switches go in: one column (a row to a switch, with its second line) or, in a short window, two.
func new_switch_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 1
	g.add_theme_constant_override("h_separation", 18)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grids.append(g)
	return g


func _switch_row(key: String, label_text: String, detail: String) -> Control:
	var row: HBoxContainer = hud._hbox(12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = hud._vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(hud._label(label_text, Fonts.sans(500), 15, ink()))
	var d := note(detail, ink3(), 13)
	d.custom_minimum_size.x = 120
	_notes.append(d)
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


# --------------------------------------------------------------------- HUD --

## HUD8, "HUD": Minimal (the default: the boards come when they matter) or Full (every board, always), side by side (the one chosen is lit), with a line of what it does under.
func _hud_row() -> Control:
	var col: VBoxContainer = hud._vbox(2)
	var row: HBoxContainer = hud._hbox(8)
	var l: Label = hud._label("HUD", Fonts.sans(500), 15, ink())
	l.custom_minimum_size.x = 112
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	for mode in HudStage.MODES:
		var b := button(String(HudStage.LABELS[mode]), false)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = String(HudStage.NOTES[mode])
		b.pressed.connect(_on_hud.bind(String(mode)))
		row.add_child(b)
		hud_buttons[String(mode)] = b
	col.add_child(row)
	hud_note = note("", ink3(), 13)
	_notes.append(hud_note)
	col.add_child(hud_note)
	return col


func _on_hud(mode: String) -> void:
	HudStage.set_mode(mode)
	_refresh_hud()
	_changed()


## The buttons and the line show the mode now.
func _refresh_hud() -> void:
	var now := HudStage.mode()
	for mode in hud_buttons:
		var b: Button = hud_buttons[mode]
		b.set_pressed_no_signal(mode == now)
		shell.restyle(b, mode == now)
	if hud_note != null:
		hud_note.text = String(HudStage.NOTES[now])


# ------------------------------------------------------------------ aiming --

## "Aiming": the two ways the mouse aims, side by side (the one chosen is lit).
func _aim_row() -> Control:
	var row: HBoxContainer = hud._hbox(8)
	var l: Label = hud._label("Aiming", Fonts.sans(500), 15, ink())
	l.custom_minimum_size.x = 112
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	for mode in AimMode.MODES:
		var b := button(String(AimMode.LABELS[mode]), false)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = _aim_words(String(mode))
		b.pressed.connect(_on_aim.bind(String(mode)))
		row.add_child(b)
		aim_buttons[String(mode)] = b
	return row


## What a way of aiming says of itself: the One House's words (nothing about orders by a right click) in the real game, the school's under `--school`.
func _aim_words(mode: String) -> String:
	if OneHouse.town_start(shell.main):
		return String(AimMode.NOTES_TOWN[mode])
	return String(AimMode.NOTES[mode])


## The real game (the prison, reached by the town start) keeps its own aim pref, the one New game writes; the school keeps `ui.aim_mode`.
func _aim_now() -> String:
	return AimMode.prison_mode() if OneHouse.town_start(shell.main) else AimMode.current()


func _on_aim(mode: String) -> void:
	if OneHouse.town_start(shell.main):
		AimMode.set_prison_mode(mode)
	else:
		AimMode.set_mode(mode)
	_refresh_aim()
	_changed()


## The buttons and the line show the mode now.
func _refresh_aim() -> void:
	var now := _aim_now()
	for mode in aim_buttons:
		var b: Button = aim_buttons[mode]
		b.set_pressed_no_signal(mode == now)
		shell.restyle(b, mode == now)
	if aim_note != null:
		aim_note.text = _aim_words(now)


## Tells the game to read the settings again (the size, the hints, fullscreen, the volumes).
func _changed() -> void:
	if shell.main != null and shell.main.has_method("apply_settings"):
		shell.main.apply_settings()
	else:
		Buses.apply_all()
		apply_fullscreen()
	shell.on_settings_changed()
