## ART PASS (round 11): the pause menu of the prison game. Esc with nothing else open pauses the tree and shows Resume, Controls, Settings (master volume) and Quit (asked twice).
## Same frame as the other windows: Hud colours, the town's fonts, a dark panel with a gold title and a thin line. Esc, or the Resume button, goes back.
## Flag: --pause (opens it at frame 20, for screenshots), --pause=controls or --pause=settings.
extends Node

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const Buses := preload("res://scripts/audio/buses.gd")
## ROUND 12: the volume sliders (label, Prefs key in section audio) and the bus each one sets.
const VOLUMES := [["Master", "master"], ["Music", "music"], ["Ambience", "ambience"], ["Effects", "sfx"]]
const BUS_OF := {"master": "Master", "music": "Music", "ambience": "Ambience", "sfx": "SFX"}

const KEYS := [
	["WASD", "walk"], ["Mouse", "aim"], ["Left button", "fire (out on a raid, or when the wall is under attack)"], ["Right button or Shift", "aim first, when Settings says so"], ["R", "reload"], ["F", "melee (shoves a hunter off)"], ["G", "throw a bottle or can: the dead go to look"],
	["E", "use, search, go out at the gate or the truck"], ["Q", "put the gun away or take it up"], ["B", "the roster"], ["C", "the squad's orders"],
	["Tab or I", "the backpack"], ["O", "fold the objectives"], ["L", "the story log: the radio messages and the convoy's list"], ["M", "the overview map"], ["Wheel", "zoom"], ["Esc", "this menu"],
]

var game
var layer: CanvasLayer
var dim: ColorRect
var panel: PanelContainer
var body: VBoxContainer
var page := "main"
var opened_frame := -10
var _quit_armed := false
var _quit_btn: Button


func setup(g) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 40
	layer.visible = false
	add_child(layer)
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(centre)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(Hud.PANEL, 0.985), Hud.LINE2, 22, 8))
	centre.add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)


func is_open() -> bool:
	return layer != null and layer.visible


func open(which: String = "main") -> void:
	if is_open():
		return
	opened_frame = Engine.get_process_frames()
	if game.audio != null:
		game.audio.ui_open()
	layer.visible = true
	get_tree().paused = not game.args.has("shot")    # (a screenshot run counts frames in the paused tree)
	_page(which)


func close() -> void:
	if not is_open():
		return
	layer.visible = false
	get_tree().paused = false
	_quit_armed = false


func _unhandled_input(ev: InputEvent) -> void:
	if not is_open() or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if (ev as InputEventKey).keycode == KEY_ESCAPE and Engine.get_process_frames() != opened_frame:
		if page == "main":
			close()
		else:
			_page("main")
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- pages --

func _page(which: String) -> void:
	page = which
	_quit_armed = false
	for c in body.get_children():
		c.queue_free()
	body.add_child(_lab("PAUSED" if which == "main" else which.to_upper(), 30, Hud.ACCENT, true))
	body.add_child(_rule())
	match which:
		"controls":
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 18)
			grid.add_theme_constant_override("v_separation", 5)
			for k in KEYS:
				if k[0] == "Mouse":
					k = ["Mouse", "aims all the time: the left button fires" if AimMode.prison_mode() == AimMode.ALWAYS else "free pointer: hold the right button (or Shift) to aim"]
				elif k[0] == "Left button" and AimMode.prison_mode() == AimMode.RIGHT:
					k = ["Left button", "fire while the right button is held (out on a raid, or when the wall is under attack)"]
				elif k[0] == "Right button or Shift":
					continue
				grid.add_child(_lab(String(k[0]), 17, Hud.ACCENT, true))
				var d := _lab(String(k[1]), 16, Hud.INK2)
				d.custom_minimum_size.x = 330
				d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				grid.add_child(d)
			body.add_child(grid)
			body.add_child(_rule())
			body.add_child(_btn("Back", func(): _page("main")))
		"settings":
			for sl_def in VOLUMES:
				body.add_child(_volume_row(String(sl_def[0]), String(sl_def[1])))
			body.add_child(_rule())
			var aim_btn := _btn("", func(): pass)
			var set_txt := func(): aim_btn.text = "Aim: " + String(AimMode.LABELS[AimMode.prison_mode()])
			set_txt.call()
			aim_btn.pressed.connect(func():
				AimMode.set_prison_mode(AimMode.RIGHT if AimMode.prison_mode() == AimMode.ALWAYS else AimMode.ALWAYS)
				set_txt.call())
			body.add_child(aim_btn)
			body.add_child(_btn("Back", func(): _page("main")))
		_:
			body.add_child(_btn("Resume", close, true))
			body.add_child(_btn("Controls", func(): _page("controls")))
			body.add_child(_btn("Settings", func(): _page("settings")))
			_quit_btn = _btn("Quit", _quit)
			body.add_child(_quit_btn)
			var tip := _lab("Esc goes back to the game", 14, Hud.INK3)
			tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(tip)


## One volume slider: the player's setting for a bus group (the same Prefs and Buses as the town's settings menu: Effects is the SFX bus and the menu sounds).
func _volume_row(label: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _lab(label, 17, Hud.INK)
	l.custom_minimum_size.x = 100
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.custom_minimum_size = Vector2(190, 24)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.value = Prefs.number("audio", key)
	var pct := _lab("%d%%" % int(sl.value * 100.0), 16, Hud.INK2)
	sl.value_changed.connect(func(v: float):
		Prefs.set_value("audio", key, v)
		Buses.apply(String(BUS_OF[key]))
		if key == "sfx":
			Prefs.set_value("audio", "ui", v)
			Buses.apply("UI")
		pct.text = "%d%%" % int(v * 100.0))
	row.add_child(sl)
	row.add_child(pct)
	return row


func _quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit_btn.text = "Really quit? Click again"
		_quit_btn.add_theme_color_override("font_color", Hud.DANGER_TEXT)
		return
	get_tree().paused = false
	get_tree().quit()


# -------------------------------------------------------------- builders --

func _box(bg: Color, line: Color, margin: int, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 14
	return s


func _lab(text: String, size: int, col: Color, cond := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.cond(700) if cond else Fonts.sans(500))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Hud.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _btn(text: String, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_override("font", Fonts.cond(700))
	b.add_theme_font_size_override("font_size", 22)
	var base := _box(Hud.ACCENT if primary else Color(Hud.PANEL_HI, 0.9), Hud.LINE2, 8, 5)
	base.shadow_size = 0
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = (Hud.ACCENT.lightened(0.15) if primary else Color(0.26, 0.34, 0.3, 0.96))
	hover.border_color = Hud.ACCENT
	var press := hover.duplicate() as StyleBoxFlat
	press.bg_color = press.bg_color.darkened(0.2)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", press)
	b.add_theme_color_override("font_color", Hud.ACCENT_INK if primary else Hud.INK)
	b.add_theme_color_override("font_hover_color", Hud.ACCENT_INK if primary else Hud.ACCENT)
	b.add_theme_color_override("font_pressed_color", Hud.ACCENT_INK if primary else Hud.ACCENT)
	b.pressed.connect(action)
	return b
