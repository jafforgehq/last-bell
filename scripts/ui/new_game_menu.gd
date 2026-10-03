## New game: how hard the nights are (Story, Standard, Brutal, each sold with a line and
## told truthfully underneath: what it really changes, from the rules' own numbers), how the
## crew begins (a small crew of three, the others calling in over the radio, or all six from
## the first morning), the length of the game (Autumn, the thirty nights as they always were, or the
## campaign of the four seasons, round 10) and the seed (a random one is shown; any whole number can be
## typed).
## Start hands the choice to the game, which reloads the scene with it. Enter starts
## straight away, so a returning player is one key from the yard; the last difficulty, the
## last crew and the last length chosen are remembered.
extends "res://scripts/ui/menu_screen.gd"

const Prefs := preload("res://scripts/prefs.gd")

const MAX_SEED_CHARS := 12
## The crews to choose from (how many people a run begins with), what each is called, a line for it on its card, and
## what it means for the game, in plain words, under the cards.
const CREWS := [3, 5, 6]
## The crew a new player begins with: five (three felt too few to do the work and send a trip).
const DEFAULT_CREW := 5
const CREW_NAMES := ["Small crew (3)", "Crew of five", "Full crew (6)"]
const CREW_LINES := [
	"Ruth, Dez and Marcus. More survivors call in over the radio.",
	"Ruth, Dez, Marcus, Ana and Walt. Hector and others call in over the radio.",
	"All six from the first morning, in the old schoolyard. Nobody calls in.",
]
const CREW_FACTS := [
	"A call can come at noon from day 2 when a bed is free (the first three callers even with the desk empty, later ones when someone is at the radio desk). Nights are smaller while the crew is.",
	"The school has six beds, so one caller fits before you build tents or a bunk house. Nights are a little smaller than the full night while the crew is.",
	"The nights are the full nights from the first day, and there are no recruits (and no town to travel to).",
]
## The lengths of the game to choose from (the campaign is round 10): what each is called and the line on its card.
const LENGTH_NAMES := ["Autumn: thirty nights", "Campaign: the four seasons"]
const LENGTH_LINES := ["Hold the wall for thirty nights.", "Autumn, Winter, Spring and Summer, each with its own Big Night."]

var difficulty := 1
## How many people the run begins with: 3 (a small crew), 5 or 6.
var crew := DEFAULT_CREW
## The three difficulty buttons, Story first.
var cards: Array = []
## The two crew buttons, the small crew first, and the words under them.
var crew_cards: Array = []
var crew_facts_label: Label
## Whether the game is the campaign of the four seasons (false: Autumn's thirty nights, the game as it was).
var campaign := false
## The two length buttons, Autumn first.
var length_cards: Array = []
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

	crew = int(Prefs.get_value("ui", "crew", DEFAULT_CREW))
	if not CREWS.has(crew):
		crew = DEFAULT_CREW
	body.add_child(section("Crew"))
	var crew_row: HBoxContainer = hud._hbox(8)
	for i in CREWS.size():
		var crew_card := _crew_card(i)
		crew_row.add_child(crew_card)
		crew_cards.append(crew_card)
	body.add_child(crew_row)
	crew_facts_label = note("", ink3(), 13)
	body.add_child(crew_facts_label)

	# a stored length that is not a plain yes is Autumn
	var stored = Prefs.get_value("ui", "campaign", false)
	campaign = typeof(stored) == TYPE_BOOL and stored
	body.add_child(section("Length"))
	var length_row: HBoxContainer = hud._hbox(8)
	for i in LENGTH_NAMES.size():
		var length_card := _length_card(i)
		length_row.add_child(length_card)
		length_cards.append(length_card)
	body.add_child(length_row)

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
	_choose_crew(CREWS.find(crew))
	_choose_length(1 if campaign else 0)


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
	var b := _pick_card(Kit.difficulty_name(i), Kit.difficulty_line(i))
	b.pressed.connect(_choose.bind(i))
	return b


## One crew: the same kind of card.
func _crew_card(i: int) -> Button:
	var b := _pick_card(CREW_NAMES[i], CREW_LINES[i])
	b.pressed.connect(_choose_crew.bind(i))
	return b


## One length of the game: the same kind of card, a little lower (it has no words under it).
func _length_card(i: int) -> Button:
	var b := _pick_card(LENGTH_NAMES[i], LENGTH_LINES[i], 88.0)
	b.pressed.connect(_choose_length.bind(i))
	return b


## A card to pick one of several: a name and a line, the whole card a button that stays pressed.
func _pick_card(title_text: String, line_text: String, min_h: float = 104.0) -> Button:
	var b := button("", false)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(120, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	var col: VBoxContainer = hud._vbox(3)
	var t: Label = hud._label(title_text, Fonts.cond(700, 1), 20, hud.INK)
	col.add_child(t)
	var s: Label = hud._label(line_text, Fonts.sans(400), 13, hud.INK2)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.custom_minimum_size.x = 60
	col.add_child(s)
	margin.add_child(col)
	b.add_child(margin)
	b.set_meta("title", t)
	b.set_meta("sub", s)
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


## Picks a crew (0 the small one, 1 the full one): its card lights up and the words under the cards say what it means.
func _choose_crew(i: int) -> void:
	i = clampi(i, 0, CREWS.size() - 1)
	crew = CREWS[i]
	for k in crew_cards.size():
		var b: Button = crew_cards[k]
		var on := k == i
		b.set_pressed_no_signal(on)
		shell.restyle(b, on)
		var t: Label = b.get_meta("title")
		var s: Label = b.get_meta("sub")
		t.add_theme_color_override("font_color", hud.ACCENT_INK if on else hud.INK)
		s.add_theme_color_override("font_color", Color(hud.ACCENT_INK, 0.86) if on else hud.INK2)
	crew_facts_label.text = CREW_FACTS[i]


## Picks a length (0 Autumn's thirty nights, 1 the campaign): its card lights up.
func _choose_length(i: int) -> void:
	i = clampi(i, 0, LENGTH_NAMES.size() - 1)
	campaign = i == 1
	for k in length_cards.size():
		var b: Button = length_cards[k]
		var on := k == i
		b.set_pressed_no_signal(on)
		shell.restyle(b, on)
		var t: Label = b.get_meta("title")
		var s: Label = b.get_meta("sub")
		t.add_theme_color_override("font_color", hud.ACCENT_INK if on else hud.INK)
		s.add_theme_color_override("font_color", Color(hud.ACCENT_INK, 0.86) if on else hud.INK2)


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
	Prefs.set_value("ui", "crew", crew)
	Prefs.set_value("ui", "campaign", campaign)
	close_sound = ""
	if campaign:
		shell.start_game(difficulty, int(parsed.value), crew, true)
	else:
		shell.start_game(difficulty, int(parsed.value), crew)
	close()
