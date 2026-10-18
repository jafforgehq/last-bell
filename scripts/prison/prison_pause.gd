## ART PASS (round 11): the pause menu of the prison game. Esc with nothing else open pauses the tree and shows Resume, Controls, Settings (master volume) and Quit (asked twice).
## Same frame as the other windows: Hud colours, the town's fonts, a dark panel with a gold title and a thin line. Esc, or the Resume button, goes back.
## Flag: --pause (opens it at frame 20, for screenshots), --pause=controls or --pause=settings.
extends Node

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const Access := preload("res://scripts/access.gd")
const BuildInfo := preload("res://scripts/build_info.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Save := preload("res://scripts/prison/prison_save.gd")    # SAVE: Save and Save and quit
## ROUND 12: the volume sliders (label, Prefs key in section audio) and the bus each one sets.
const VOLUMES := [["Master", "master"], ["Music", "music"], ["Ambience", "ambience"], ["Effects", "sfx"]]
const BUS_OF := {"master": "Master", "music": "Music", "ambience": "Ambience", "sfx": "SFX"}

const KEYS := [
	["WASD", "walk"], ["Mouse", "aim"], ["Left button", "fire (out on a raid, or when the wall is under attack)"], ["Right button or Shift", "aim first, when Settings says so"], ["R", "reload"], ["F", "stab with the knife, any time (quiet; shoves a hunter off)"], ["G", "throw a bottle or can: the dead go to look"], ["T", "throw a signal flare at the pointer: eight seconds of red light and noise that pull the dead within 25 tiles"], ["Middle button", "ping a spot in a raid or the clear phase: the squad runs there and holds (20 s)"],
	["E", "use, search, go out at the gate or the truck"], ["Q", "put the gun away or take it up"], ["B", "the Base screen"], ["C", "the squad's orders"], ["V", "retreat: the whole squad runs to the nearest pickup ring (V again: stand down)"],
	["Tab or I", "the backpack"], ["O", "fold the objectives"], ["L", "the story log: the radio messages and the convoy's list"], ["M", "the overview map"], ["F1 F2 F3", "base speed 1x, 2x, 3x (also - and =)"], ["Wheel", "zoom"], ["Esc", "this menu"],
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
var _save_note := ""    # SAVE: what the last press of Save said


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
	var fr: StyleBox = Hud.frame("panel")    # the chalkboard in oak trim of the title, New game and Settings screens (flat when the picture is missing)
	if fr != null:
		fr.content_margin_left = 30
		fr.content_margin_right = 30
		fr.content_margin_top = 26
		fr.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", fr if fr != null else _box(Color(Hud.PANEL, 0.985), Hud.LINE2, 22, 8))
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
	_save_note = ""
	if game.audio != null:
		game.audio.ui_open()
	layer.visible = true
	if game.prompt_label != null:
		game.prompt_label.visible = false    # (the tree stops: the E prompt would stay up, peeking out at both sides of the menu)
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
				d.custom_minimum_size.x = 380
				d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				grid.add_child(d)
			var gsc := ScrollContainer.new()    # (the list scrolls; Back stays under it)
			gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			gsc.custom_minimum_size = Vector2(560, clampf(game._vp().y - 250.0, 200.0, 460.0))
			gsc.add_child(grid)
			body.add_child(gsc)
			body.add_child(_rule())
			body.add_child(_btn("Back", func(): _page("main")))
		"event log":    # META: every morning card answered this run
			var log: Array = game.arc.event_log
			if log.is_empty():
				body.add_child(_lab("No morning cards yet.", 16, Hud.INK3))
			var sc := ScrollContainer.new()
			sc.custom_minimum_size = Vector2(520, minf(360.0, 60.0 * float(log.size()) + 10.0))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 8)
			sc.add_child(col)
			for i in range(log.size() - 1, -1, -1):
				var e: Dictionary = log[i]
				col.add_child(_lab("Day %d   %s" % [int(e.day), String(e.title)], 17, Hud.INK, true))
				var c := _lab("You chose: " + String(e.choice), 14, Hud.INK2)
				c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				c.custom_minimum_size.x = 500
				col.add_child(c)
			body.add_child(sc)
			body.add_child(_rule())
			body.add_child(_btn("Back", func(): _page("main")))
		"settings":
			for sl_def in VOLUMES:
				body.add_child(_volume_row(String(sl_def[0]), String(sl_def[1])))
			body.add_child(_rule())
			body.add_child(_text_row())
			body.add_child(_shake_row())
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
			body.add_child(_btn("Event log", func(): _page("event log")))
			_save_rows()
			body.add_child(report_row(game.arc.plog, "Copy report"))
			_quit_btn = _btn("Quit", _quit)
			body.add_child(_quit_btn)
			var run_l := _lab("%s   seed %d" % [game.Bal.dm("name", "Standard"), game.Bal.run_seed], 14, Hud.INK3)
			run_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(run_l)
			var tip := _lab("Esc goes back to the game   |   build " + BuildInfo.VERSION, 14, Hud.INK3)
			tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(tip)


## PLAYLOG: a one-line notes box and the "Copy report" button (also used by the ending card). The note goes in the report; the box keeps the keys to itself while it has focus.
func report_row(plog, label: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var le := LineEdit.new()
	le.placeholder_text = "What felt wrong? (optional, one line)"
	le.max_length = 200
	le.text = plog.notes
	le.add_theme_font_override("font", Fonts.sans(500))
	le.add_theme_font_size_override("font_size", 16)
	le.text_changed.connect(func(t: String): plog.notes = t)
	le.visible = "playtest" in BuildInfo.VERSION    # (the tester's box: only in a playtest build)
	col.add_child(le)
	var b := _btn(label, func(): pass)
	b.pressed.connect(func():
		plog.copy_report()
		b.text = "Copied. Send it to Fedja")
	col.add_child(b)
	return col


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


## "Text size": three stops (Normal, Large, Larger: the setting scripts/access.gd keeps, which never draws under the original size); the words change at once.
func _text_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _lab("Text size", 17, Hud.INK)
	l.custom_minimum_size.x = 100
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = float(Access.TEXT_SIZES.size() - 1)
	sl.step = 1.0
	sl.tick_count = Access.TEXT_SIZES.size()
	sl.custom_minimum_size = Vector2(190, 24)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.value = float(maxi(0, Access.TEXT_SIZES.find(Access.text_size())))
	var name_l := _lab(String(Access.TEXT_LABELS[Access.text_size()]), 16, Hud.INK2)
	name_l.custom_minimum_size.x = 56
	sl.value_changed.connect(func(v: float):
		var id := String(Access.TEXT_SIZES[int(v)])
		Prefs.set_value("ui", "text_size", id)
		name_l.text = String(Access.TEXT_LABELS[id])
		if game.text_scale != null:
			game.text_scale.refresh())
	row.add_child(sl)
	row.add_child(name_l)
	return row


## "Screen shake": 0 to 100 percent of every camera kick, shake and nudge (Access.shake_k; the camera reads it twice a second).
func _shake_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _lab("Screen shake", 17, Hud.INK)
	l.custom_minimum_size.x = 100
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.custom_minimum_size = Vector2(190, 24)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.value = Access.shake_k() * 100.0
	var pct := _lab("%d%%" % int(sl.value), 16, Hud.INK2)
	pct.custom_minimum_size.x = 56
	sl.value_changed.connect(func(v: float):
		Prefs.set_value("ui", "shake", v / 100.0)
		game.fx.combat.shake_k = v / 100.0
		pct.text = "%d%%" % int(v))
	row.add_child(sl)
	row.add_child(pct)
	return row


## SAVE: the two buttons, grey (with the reason under them) when the game cannot be saved now.
func _save_rows() -> void:
	var why := Save.why_not(game)
	for row in [["Save", false], ["Save and quit", true]]:
		var b := _btn(String(row[0]), _save.bind(bool(row[1])))
		b.disabled = why != ""
		b.modulate.a = 0.45 if why != "" else 1.0
		body.add_child(b)
	var note := why if why != "" else _save_note
	if note != "":
		var l := _lab(note, 14, Hud.INK2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 330
		body.add_child(l)


func _save(and_quit: bool) -> void:
	var err: String = Save.write(game, "manual")
	_save_note = "Saved." if err == "" else err
	if err == "" and and_quit:
		get_tree().paused = false
		get_tree().quit()
		return
	_page("main")


func _quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit_btn.text = "Really quit? Click again"
		_quit_btn.add_theme_color_override("font_color", Hud.DANGER_TEXT)
		return
	game.arc.plog.quit_at()    # PLAYLOG hook: where the player quit
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
	var looks: Array = [base, hover, press]
	var kinds: Array = ["button_primary", "button_primary_hover", "button_primary_pressed"] if primary else ["button", "button_hover", "button_pressed"]
	for i in 3:    # the menus' framed buttons when their pictures are there
		var f: StyleBox = Hud.frame(String(kinds[i]))
		if f != null:
			f.content_margin_top = 0
			f.content_margin_bottom = 0
			looks[i] = f
	b.add_theme_stylebox_override("normal", looks[0])
	b.add_theme_stylebox_override("hover", looks[1])
	b.add_theme_stylebox_override("pressed", looks[2])
	b.add_theme_color_override("font_color", Hud.ACCENT_INK if primary else Hud.INK)
	b.add_theme_color_override("font_hover_color", Hud.ACCENT_INK if primary else Hud.ACCENT)
	b.add_theme_color_override("font_pressed_color", Hud.ACCENT_INK if primary else Hud.ACCENT)
	b.pressed.connect(action)
	return b
