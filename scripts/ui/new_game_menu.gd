## New game: how hard the nights are (Story, Standard, Brutal, each sold with a line and
## told truthfully underneath: what it really changes, from the rules' own numbers) and the
## seed (a random one is shown; any whole number can be typed). Start hands the choice to
## the game, which reloads the scene with it. Enter starts straight away, so a returning
## player is one key from the yard; the last difficulty chosen is remembered.
extends "res://scripts/ui/menu_screen.gd"

const Prefs := preload("res://scripts/prefs.gd")

const MAX_SEED_CHARS := 12

var difficulty := 1
## The three difficulty buttons, Story first.
var cards: Array = []
var facts_label: Label
var seed_edit: LineEdit
var seed_error: Label
var random_button: Button
var back_button: Button
var start_button: Button


func _init() -> void:
	kind = "new"
	max_w = 600.0


## A seed typed by the player: {"ok": true, "value": n} for a whole number, else {"ok": false,
## "why": words}.
static func parse_seed(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {"ok": false, "why": "Type a whole number, or press Random."}
	if t.length() > MAX_SEED_CHARS or not t.is_valid_int():
		return {"ok": false, "why": "A seed is a whole number, like 482913."}
	return {"ok": true, "value": t.to_int()}


## A seed to show when the screen opens, and when Random is pressed.
static func random_seed() -> int:
	return randi_range(100000, 999999)


func _build_body() -> void:
	difficulty = clampi(int(Prefs.get_value("ui", "difficulty", 1)), 0, 2)
	body.add_child(section("Difficulty"))
	var row: HBoxContainer = hud._hbox(8)
	for i in 3:
		var card := _card(i)
		row.add_child(card)
		cards.append(card)
	body.add_child(row)
	var slip: PanelContainer = hud._panel(hud._style(Color(hud.PANEL_HI, 0.7), 6, hud.LINE, false, "panel_inset"))
	facts_label = note("", ink(), 14)
	slip.add_child(facts_label)
	body.add_child(slip)

	body.add_child(section("Seed"))
	var seed_row: HBoxContainer = hud._hbox(8)
	seed_edit = LineEdit.new()
	seed_edit.text = str(random_seed())
	seed_edit.placeholder_text = "Any whole number"
	seed_edit.max_length = MAX_SEED_CHARS
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	seed_edit.custom_minimum_size = Vector2(150, 42)
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_edit(seed_edit)
	seed_edit.text_changed.connect(_on_seed_changed)
	seed_edit.text_submitted.connect(func(_t): _start())
	seed_row.add_child(seed_edit)
	random_button = button("Random", false)
	random_button.pressed.connect(_on_random)
	seed_row.add_child(random_button)
	body.add_child(seed_row)
	seed_error = note("", hud.DANGER_TEXT, 13)
	seed_error.visible = false
	body.add_child(seed_error)
	body.add_child(note("Any whole number. The same seed and the same orders play the same game.", ink3(), 13))
	_choose(difficulty)


func _build_foot() -> void:
	back_button = button("Back", false)
	back_button.pressed.connect(close)
	foot.add_child(back_button)
	start_button = button("Start", true)
	start_button.pressed.connect(_start)
	foot.add_child(start_button)


func default_focus() -> Control:
	return start_button


## One difficulty: its name and its line, the whole card a button that stays pressed.
func _card(i: int) -> Button:
	var b := button("", false)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(120, 104)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	var col: VBoxContainer = hud._vbox(3)
	var t: Label = hud._label(Kit.difficulty_name(i), Fonts.cond(700, 1), 20, hud.INK)
	col.add_child(t)
	var s: Label = hud._label(Kit.difficulty_line(i), Fonts.sans(400), 13, hud.INK2)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.custom_minimum_size.x = 60
	col.add_child(s)
	margin.add_child(col)
	b.add_child(margin)
	b.set_meta("title", t)
	b.set_meta("sub", s)
	b.pressed.connect(_choose.bind(i))
	return b


func _style_edit(e: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.34)
	normal.border_color = hud.LINE2
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	e.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = hud.ACCENT
	focus.set_border_width_all(2)
	e.add_theme_stylebox_override("focus", focus)
	e.add_theme_font_override("font", Fonts.sans(500))
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", hud.INK)
	e.add_theme_color_override("font_placeholder_color", hud.INK3)
	e.add_theme_color_override("caret_color", hud.ACCENT)
	e.add_theme_color_override("selection_color", Color(hud.ACCENT, 0.4))


## Picks a difficulty: its card lights up and the words under the cards say what it does.
func _choose(i: int) -> void:
	difficulty = clampi(i, 0, 2)
	for k in cards.size():
		var b: Button = cards[k]
		var on := k == difficulty
		b.set_pressed_no_signal(on)
		shell.restyle(b, on)
		var t: Label = b.get_meta("title")
		var s: Label = b.get_meta("sub")
		t.add_theme_color_override("font_color", hud.ACCENT_INK if on else hud.INK)
		s.add_theme_color_override("font_color", Color(hud.ACCENT_INK, 0.86) if on else hud.INK2)
	facts_label.text = Kit.difficulty_facts(difficulty)


func _on_random() -> void:
	seed_edit.text = str(random_seed())
	_on_seed_changed(seed_edit.text)


func _on_seed_changed(text: String) -> void:
	var parsed := parse_seed(text)
	seed_error.visible = not parsed.ok
	seed_error.text = String(parsed.get("why", ""))
	start_button.disabled = not parsed.ok


func _start() -> void:
	var parsed := parse_seed(seed_edit.text)
	if not parsed.ok:
		_on_seed_changed(seed_edit.text)
		shell.play("ui_error")
		return
	Prefs.set_value("ui", "difficulty", difficulty)
	close_sound = ""
	shell.start_game(difficulty, int(parsed.value))
	close()
