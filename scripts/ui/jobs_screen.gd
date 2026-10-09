## The Jobs screen, the Duty roster: a page of notebook paper over the game (key J, the clipboard in the toolbar,
## or the job tag in a person's panel). A row for each person: their picture, name and mood, their **day job**
## (a station: a button that opens the short list of the stations with their seats left, the full ones off, and
## "No job") and their **night post** (a button that opens the list of the posts on the wall, a taken one greyed
## with who holds it), their skills with the one their station asks for marked, and what they are doing now.
## Under the table the stations: what each does, its seats (a picture of whoever sits in each) and its settings
## as sliders (the bench's ammo target and scrap reserve, the wall crew's threshold). The buttons Auto-assign
## (fills the seats by skill and trait) and Clear (takes everyone off their jobs) and Close are at the foot.
##
## Hovering (or putting the keyboard on) a row, a station or a post marks its place in the world: the HUD hands
## `{"station", "post", "person"}` to main.gd (`show_marks`, hud.on_jobs_hover), which the overlay draws. With the
## page up, every station is marked faintly.
##
## Everything is read from the jobs module (sim.jobs: stations, job_of, crew_of, seats_left, why_not, assign, clear,
## auto_assign, setting, set_setting, posts, post_of, set_post) and changed through it. The people who are dead,
## turned or away are shown as such and cannot be given anything. Mouse and keyboard: every control can have the
## keyboard (Tab, Shift+Tab and the arrows go between them, Enter or Space presses a button and opens a list, the arrows
## and Enter choose in a list, the arrows move a slider); Esc closes the list, then the screen; J closes the screen.
## Opened by hud.open_jobs, which also pauses the rules while it is open and gives the speed back.
##
## It borrows the HUD's styles, colours and icons (the `hud` it is given) so it looks like the rest; the ink on
## the page is the HUD's PAPER_INK family (the chalk colours are for the boards).
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")

## Emitted once, when the screen is gone.
signal closed

## The page is at most this wide, and keeps MARGIN from the window's edge.
const MAX_W := 960.0
const MARGIN := 12.0
## The widths of the cells of a person's row: who, the day job, the night post, the skills, what they are doing.
const CELL_WHO := 124.0
const CELL_JOB := 172.0
const CELL_POST := 204.0
const CELL_SKILLS := 148.0
const CELL_DOING := 160.0
const CELL_GAP := 10.0
## A skill's cell in the grid of a row (so that the numbers line up from row to row).
const SKILL_W := 71.0
## A row's own margin, left and right; with the cells it is what the table asks for on one line (narrower, the
## cells run on to a second line and the column captions are written in the cells).
const ROW_PAD := 6.0
const TABLE_W := CELL_WHO + CELL_JOB + CELL_POST + CELL_SKILLS + CELL_DOING + CELL_GAP * 4.0 + ROW_PAD * 2.0
const PORTRAIT_PX := 34
## The room kept at the right of the words for the scroll bar.
const GUTTER := 14
## A station's card is never narrower than this; as many go side by side as the room allows (up to three).
const STATION_W := 270.0
const STATION_GAP := 10.0
const SEAT_PX := 24
## The list that opens from a button: as wide as this at least, and as tall as this at most (it scrolls).
const LIST_W := 280.0
const LIST_MAX_H := 380.0
const SKILLS := ["Shooting", "Building", "Medicine", "Leading"]
## The veil over the game, and how the page and the veil fade while a place on a list is under the mouse (a peek at the world:
## the page is under the list, which stays solid, and the marks drawn in the yard show through).
const DIM := 0.5
const PEEK_PAGE := 0.1
const PEEK_DIM := 0.22
const PEEK_SECONDS := 0.12
## A mood in words, as ink on paper (the chalk colours are for the boards), and the ink of "Away": each at 4.5:1 or better on
## the page whatever its picture (tests/test_jobs_screen.gd computes it).
const MOOD_INK := {"Inspired": Dialog.GOLD_INK, "Shaken": Color("#7d430a")}
const INK_AWAY := Color("#1f5073")

var hud
var sim
var jobs
var panel: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var table_head: Control
var rows_box: VBoxContainer
var stations_box: GridContainer
var stations_caption: Label
var auto_button: Button
var clear_button: Button
var close_button: Button
var error_label: Label
var hint_label: Label
## person id -> {"person", "row", "who", "name", "mood", "job", "job_icon", "job_text", "post", "post_text", "skills" (skill ->
## the cell, whose meta "marked" says whether the station asks for it), "doing", "captions" (the small column headings of a
## narrow row)}
var rows := {}
## station id -> {"station", "card", "pips" (a panel for each seat: its meta "who" is the person's id, or ""), "crew" (the label), "sliders"
## (setting -> HSlider), "values" (setting -> the label with its value)}
var station_cards := {}
## The list that is open (a panel), or null: its kind ("job" or "post"), the person it is for, and its items by id
## (a station's or a post's; "" is "No job").
var list = null
var list_kind := ""
var list_for = null
var list_items := {}
var _list_opener: Button = null
var _list_catcher: Control = null
var _list_scroll: ScrollContainer = null
var _list_box: VBoxContainer = null
var _list_caption: Label = null
var _list_hint: Label = null
var _first_focus := false
## Whether the page is faded to show the world under it (a place on a list is under the mouse).
var peeking := false
var _dim: ColorRect
var _fade: Tween
var _open := true
var _wide := true
var _page: Control
var _head: Control
var _foot: Control
var _captions: Array = []
var _sig := ""
var _marks := {}


## `h` is the HUD, `s` the game: the screen reads the jobs from `s.jobs`.
func setup(h, s) -> void:
	hud = h
	sim = s
	jobs = sim.jobs
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# a page over the whole window: the HUD knows it as a modal (the speech bubbles keep quiet under it)
	set_meta("modal", true)
	_build()
	refresh(true)
	resized.connect(_layout)
	# a line that wraps, or a row that runs on to a second line, makes the body taller: the scroll's room follows
	body.minimum_size_changed.connect(func(): _layout.call_deferred())
	_layout()
	# wrapped text only knows its height once it has a width: lay out again a frame on
	_layout.call_deferred()
	# every station is marked faintly; nothing has the keyboard yet (a first Tab or arrow puts it on the first job)
	show_marks()


# ------------------------------------------------------------------- build --

func _build() -> void:
	# lighter than the dialogs' veil: the yard shows round the page, where the marks of what is hovered are drawn
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.04, 0.035, DIM)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_page = CenterContainer.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)
	panel = hud._panel(hud._paper_style())
	_page.add_child(panel)
	var col: VBoxContainer = hud._vbox(8)
	panel.add_child(col)

	# the title, and beside it (under it when there is no room) what the page is for
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 14)
	head.add_theme_constant_override("v_separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hud._label("Duty roster", Fonts.cond(700), 26, hud.PAPER_INK))
	var sub: Label = hud._caps("Who works where by day, and who holds which post at night", hud.PAPER_INK2)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	_head = head
	col.add_child(head)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(scroll)
	col.add_child(scroll)
	# a gutter at the right for the scroll bar, so that it never sits over the words
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", GUTTER)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gutter)
	body = hud._vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(body)

	table_head = _build_table_head()
	body.add_child(table_head)
	rows_box = hud._vbox(0)
	for p in sim.people:
		rows_box.add_child(_build_row(p))
	body.add_child(rows_box)
	stations_caption = hud._caps("Stations", hud.PAPER_INK2)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(stations_caption)
	body.add_child(pad)
	stations_box = GridContainer.new()
	stations_box.columns = 3
	stations_box.add_theme_constant_override("h_separation", int(STATION_GAP))
	stations_box.add_theme_constant_override("v_separation", int(STATION_GAP))
	stations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stations_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for st in jobs.stations():
		stations_box.add_child(_build_station(st))
	body.add_child(stations_box)

	var foot: VBoxContainer = hud._vbox(6)
	error_label = hud._label("", Fonts.sans(600), 13, hud.SLIP_MARK.danger)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.custom_minimum_size.x = 160
	error_label.visible = false
	foot.add_child(error_label)
	var row: HBoxContainer = hud._hbox(10)
	hint_label = hud._label("Pick a day job or a night post from a person's row. J or Esc closes.", Fonts.sans(400), 13, hud.PAPER_INK2)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label.custom_minimum_size.x = 120
	row.add_child(hint_label)
	auto_button = _button("Auto-assign")
	auto_button.tooltip_text = "Auto-assign: take everyone off their jobs and fill the seats by skill and trait"
	auto_button.pressed.connect(auto_assign)
	row.add_child(auto_button)
	clear_button = _button("Clear")
	clear_button.tooltip_text = "Clear: take everyone off their jobs (the night posts stay)"
	clear_button.pressed.connect(clear_jobs)
	row.add_child(clear_button)
	close_button = _button("Close", true)
	close_button.tooltip_text = "Close the roster\nKey: J"
	close_button.pressed.connect(close)
	row.add_child(close_button)
	foot.add_child(row)
	_foot = foot
	col.add_child(foot)


## A button of the HUD's kind on a page that the keyboard can reach (the HUD's own never take focus).
func _button(text: String, primary: bool = false) -> Button:
	var b: Button = hud._button(text, primary, true)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("focus", Kit.focus_box(hud.INK if primary else hud.ACCENT))
	return b


## The page's scroll bar in the page's colours: a pencil-line track and an oak knob.
func _style_scrollbar(box: ScrollContainer) -> void:
	var bar := box.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(hud.PAPER_INK, 0.1)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	var knobs := {"grabber": hud.OAK, "grabber_highlight": hud.OAK.lightened(0.15), "grabber_pressed": hud.OAK_DARK}
	for knob_name in knobs:
		var knob := StyleBoxFlat.new()
		knob.bg_color = knobs[knob_name]
		knob.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(knob_name, knob)
	bar.custom_minimum_size.x = 9


# -------------------------------------------------------------------- the table --

## The captions over the columns (only while the table is on one line: a narrow one writes them in its cells).
func _build_table_head() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(CELL_GAP))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in [["Person", CELL_WHO], ["Day job", CELL_JOB], ["Night post", CELL_POST], ["Skills", CELL_SKILLS], ["Doing now", CELL_DOING]]:
		var l: Label = hud._caps(String(pair[0]), hud.PAPER_INK3)
		l.custom_minimum_size.x = float(pair[1])
		head.add_child(l)
	# the columns start where a row's cells do: inside its margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(ROW_PAD))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(head)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(margin)
	wrap.add_child(_rule(hud.PAPER_INK))
	return wrap


func _rule(color: Color = Color(0, 0, 0, 0)) -> Control:
	var r := ColorRect.new()
	r.color = color if color.a > 0.0 else hud.PAPER_LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The look of a row: clear, a pencil rule under it; gold-washed while it is the one the mouse or the keyboard is on.
func _row_style(lit: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Dialog.CARD_CHOSEN, 0.6) if lit else Color(0, 0, 0, 0)
	s.border_color = hud.PAPER_LINE
	s.border_width_bottom = 1
	s.content_margin_left = ROW_PAD
	s.content_margin_right = ROW_PAD
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


## A column of a row: a small caption (shown only in a narrow table) over the content, `width` wide.
func _cell(caption: String, width: float, content: Control) -> Control:
	var box: VBoxContainer = hud._vbox(1)
	box.custom_minimum_size.x = width
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caption != "":
		var l: Label = hud._caps(caption, hud.PAPER_INK3)
		l.visible = not _wide
		_captions.append(l)
		box.add_child(l)
	box.add_child(content)
	return box


func _build_row(p) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", _row_style(false))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(CELL_GAP))
	flow.add_theme_constant_override("v_separation", 2)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(flow)
	var r := {"person": p, "row": row, "skills": {}, "captions": []}

	# who: the picture, the name and the mood
	var who: HBoxContainer = hud._hbox(8)
	who.custom_minimum_size.x = CELL_WHO
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pic := TextureRect.new()
	pic.texture = hud.portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(pic)
	var names: VBoxContainer = hud._vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label: Label = hud._label(p.first, Fonts.cond(700), 18, hud.PAPER_INK)
	names.add_child(name_label)
	var mood: Label = hud._label("", Fonts.sans(600), 13, hud.PAPER_INK2)
	names.add_child(mood)
	who.add_child(names)
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	who.tooltip_text = "%s, %s" % [p.name, String(p.def.role).to_lower()]
	flow.add_child(who)
	r["who"] = who
	r["name"] = name_label
	r["mood"] = mood

	# the day job and the night post: buttons that open a list
	var job := _picker("Day job for %s" % p.first)
	r["job"] = job.button
	r["job_icon"] = job.icon
	r["job_text"] = job.text
	job.button.pressed.connect(open_job_list.bind(p))
	flow.add_child(_cell("Day job", CELL_JOB, job.button))
	var post := _picker("Night post for %s" % p.first)
	post.icon.texture = hud.icons.get("moon")
	r["post"] = post.button
	r["post_icon"] = post.icon
	r["post_text"] = post.text
	post.button.pressed.connect(open_post_list.bind(p))
	flow.add_child(_cell("Night post", CELL_POST, post.button))

	# the skills, two by two, the one their station asks for marked
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for skill in SKILLS:
		var cell := _skill_cell(String(skill))
		grid.add_child(cell)
		r.skills[skill] = cell
	flow.add_child(_cell("Skills", CELL_SKILLS, grid))

	# what they are doing now
	var doing: Label = hud._label("", Fonts.sans(400), 13, hud.PAPER_INK2)
	doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	doing.max_lines_visible = 2
	doing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	doing.custom_minimum_size = Vector2(CELL_DOING, 34)
	doing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	doing.mouse_filter = Control.MOUSE_FILTER_PASS
	flow.add_child(_cell("Doing now", CELL_DOING, doing))
	r["doing"] = doing

	row.mouse_entered.connect(_on_row_hover.bind(p, true))
	row.mouse_exited.connect(_on_row_hover.bind(p, false))
	for b in [job.button, post.button]:
		b.focus_entered.connect(_on_row_hover.bind(p, true))
		b.focus_exited.connect(_on_row_hover.bind(p, false))
	rows[p.id] = r
	return row


## One skill in a row: its name and its number; the skill the person's station asks for has a gold wash.
func _skill_cell(skill: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_theme_stylebox_override("panel", _skill_style(false))
	cell.custom_minimum_size.x = SKILL_W
	var box: HBoxContainer = hud._hbox(4)
	box.add_child(hud._label(skill, Fonts.sans(400), 12, hud.PAPER_INK2))
	var number: Label = hud._label("0", Fonts.cond(700), 14, hud.PAPER_INK)
	box.add_child(number)
	cell.add_child(box)
	cell.set_meta("marked", false)
	cell.set_meta("number", number)
	return cell


func _skill_style(marked: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Dialog.CARD_CHOSEN if marked else Color(0, 0, 0, 0)
	s.border_color = Dialog.GOLD_EDGE if marked else Color(0, 0, 0, 0)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	return s


## One of those buttons: a field of the page (a lighter sheet with a pencil edge, gold under the mouse) with the
## station's or the moon's picture, its words and a little chevron. {"button", "icon", "text"}.
func _picker(tip: String) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, _field_style(state))
	b.add_theme_stylebox_override("focus", Kit.focus_box(Dialog.GOLD_EDGE, 5))
	b.tooltip_text = tip
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 6)
	var inner: HBoxContainer = hud._hbox(6)
	var icon: TextureRect = hud._icon("", 16, hud.PAPER_INK2)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(icon)
	var text: Label = hud._label("", Fonts.sans(500), 14, hud.PAPER_INK)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(text)
	var chevron := Chevron.new()
	chevron.color = hud.PAPER_INK2
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(chevron)
	pad.add_child(inner)
	b.add_child(pad)
	return {"button": b, "icon": icon, "text": text}


## The look of a field: `state` is normal, hover, pressed or disabled.
func _field_style(state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Dialog.CARD
	s.border_color = Color(hud.PAPER_INK, 0.38)
	match state:
		"hover":
			s.bg_color = Dialog.CARD_CHOSEN
			s.border_color = Dialog.GOLD_EDGE
		"pressed":
			s.bg_color = Dialog.CARD_CHOSEN.darkened(0.06)
			s.border_color = Dialog.GOLD_EDGE
		"disabled":
			s.bg_color = Color(Dialog.CARD, 0.45)
			s.border_color = Color(hud.PAPER_INK, 0.2)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.anti_aliasing = true
	return s


## A small "v" at the end of a field: the field opens a list.
class Chevron:
	extends Control
	var color := Color.BLACK

	func _init() -> void:
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		draw_polyline(PackedVector2Array([c + Vector2(-4.0, -2.0), c + Vector2(0.0, 2.0), c + Vector2(4.0, -2.0)]), color, 2.0, true)


# ------------------------------------------------------------------ the stations --

## A card for a station: its name and picture, its seats (the picture of whoever sits in each), what it does and
## its settings as sliders.
func _build_station(st: Dictionary) -> Control:
	var id := String(st.id)
	var card: PanelContainer = hud._panel(_card_style(false))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.custom_minimum_size.x = STATION_W
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	var col: VBoxContainer = hud._vbox(4)
	var head: HBoxContainer = hud._hbox(8)
	var icon: TextureRect = hud._icon(String(st.get("icon", "")), 20, hud.PAPER_INK2)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var title: Label = hud._label(String(st.name), Fonts.cond(700), 18, hud.PAPER_INK)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(hud._spacer())
	var seats: HBoxContainer = hud._hbox(3)
	seats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pips: Array = []
	for i in int(st.seats):
		var pip := _seat()
		seats.add_child(pip)
		pips.append(pip)
	head.add_child(seats)
	col.add_child(head)
	var blurb: Label = hud._label(String(st.get("blurb", "")), Fonts.sans(400), 13, hud.PAPER_INK2)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 120
	col.add_child(blurb)
	var crew: Label = hud._label("", Fonts.sans(600), 13, hud.PAPER_INK)
	crew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crew.custom_minimum_size.x = 120
	col.add_child(crew)
	var c := {"station": st, "card": card, "pips": pips, "crew": crew, "sliders": {}, "values": {}}
	for key in st.settings:
		col.add_child(_setting(c, id, String(key), st.settings[key]))
	card.add_child(col)
	card.tooltip_text = "%s (%s)\n%d seats" % [String(st.name), String(st.get("where", "")), int(st.seats)]
	card.mouse_entered.connect(_on_station_hover.bind(id, true))
	card.mouse_exited.connect(_on_station_hover.bind(id, false))
	station_cards[id] = c
	return card


## A card of the page: a sheet a little lighter than the paper with a thin ink edge (a gold wash and a heavy edge
## of dark gold while the mouse or the keyboard is on it).
func _card_style(lit: bool) -> StyleBox:
	var s: StyleBoxFlat = hud._flat(Dialog.CARD_CHOSEN if lit else Dialog.CARD, 4, Dialog.GOLD_EDGE if lit else Color(hud.PAPER_INK, 0.3), false)
	s.set_border_width_all(2 if lit else 1)
	s.content_margin_left = 11
	s.content_margin_right = 11
	s.content_margin_top = 8
	s.content_margin_bottom = 9
	return s


## One seat of a station: a small square with the picture of whoever sits in it, or empty.
func _seat() -> Panel:
	var pip := Panel.new()
	pip.custom_minimum_size = Vector2(SEAT_PX, SEAT_PX)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pip.mouse_filter = Control.MOUSE_FILTER_PASS
	pip.clip_contents = true
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.add_child(pic)
	pip.set_meta("pic", pic)
	pip.set_meta("who", "")
	pip.add_theme_stylebox_override("panel", _seat_style(false))
	return pip


func _seat_style(filled: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Dialog.CARD_CHOSEN if filled else Color(hud.PAPER_INK, 0.06)
	s.border_color = Dialog.GOLD_EDGE if filled else Color(hud.PAPER_INK, 0.4)
	s.set_border_width_all(2 if filled else 1)
	s.set_corner_radius_all(4)
	return s


## A setting of a station: what it is, a slider and its value with its unit.
func _setting(c: Dictionary, station_id: String, key: String, def: Dictionary) -> Control:
	var box: VBoxContainer = hud._vbox(0)
	var label: Label = hud._label(String(def.get("label", key)), Fonts.sans(400), 13, hud.PAPER_INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120
	box.add_child(label)
	var row: HBoxContainer = hud._hbox(8)
	var s := HSlider.new()
	s.min_value = float(def.min)
	s.max_value = float(def.max)
	s.step = float(def.step)
	s.value = float(jobs.setting(station_id, key))
	s.scrollable = false
	s.focus_mode = Control.FOCUS_ALL
	# (the wheel is for the page's scroll, not the slider's: it passes it on)
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.custom_minimum_size = Vector2(90, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = String(def.get("label", key))
	_style_slider(s)
	row.add_child(s)
	var value: Label = hud._label(_value_text(def, s.value), Fonts.cond(700), 15, hud.PAPER_INK)
	value.custom_minimum_size.x = 70
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	box.add_child(row)
	c.sliders[key] = s
	c.values[key] = value
	s.value_changed.connect(_on_setting.bind(station_id, key))
	s.focus_entered.connect(_on_station_hover.bind(station_id, true))
	s.focus_exited.connect(_on_station_hover.bind(station_id, false))
	return box


## A slider was moved: the jobs module keeps the value (inside its range and its steps) and the page shows what it kept.
func _on_setting(value: float, station_id: String, key: String) -> void:
	jobs.set_setting(station_id, key, value)
	var now := float(jobs.setting(station_id, key))
	var c: Dictionary = station_cards[station_id]
	var s: HSlider = c.sliders[key]
	if not is_equal_approx(s.value, now):
		s.set_value_no_signal(now)
	c.values[key].text = _value_text(c.station.settings[key], now)


## "300 ammo", "70%": a setting's value with its unit.
static func _value_text(def: Dictionary, value: float) -> String:
	var unit := String(def.get("unit", ""))
	if unit == "%":
		return "%d%%" % roundi(value)
	return "%d %s" % [roundi(value), unit] if unit != "" else "%d" % roundi(value)


## A slider in the page's colours: a pencil-line groove, an oak fill and a paper knob with an oak rim.
func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(hud.PAPER_INK, 0.2)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = hud.OAK
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = hud.OAK.lightened(0.15)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", Kit.disc(9, Dialog.CARD, hud.OAK_DARK, 3.0))
	s.add_theme_icon_override("grabber_highlight", Kit.disc(10, Dialog.CARD_CHOSEN, hud.OAK_DARK, 3.0))
	s.add_theme_stylebox_override("focus", Kit.focus_box(Dialog.GOLD_EDGE, 4))


# ----------------------------------------------------------------------- layout --

func _layout() -> void:
	if panel == null or not is_inside_tree():
		return
	var pw := minf(size.x - 2.0 * MARGIN, MAX_W)
	panel.custom_minimum_size.x = maxf(pw, 0.0)
	var frame: StyleBox = panel.get_theme_stylebox("panel")
	var inner := pw - frame.get_margin(SIDE_LEFT) - frame.get_margin(SIDE_RIGHT) - float(GUTTER)
	# the table on one line, with its captions over the columns, while there is room; else its rows run on
	var wide := inner >= TABLE_W
	if wide != _wide:
		_wide = wide
	table_head.visible = _wide
	for l in _captions:
		l.visible = not _wide
	var cols := clampi(int((inner + STATION_GAP) / (STATION_W + STATION_GAP)), 1, 3)
	stations_box.columns = cols
	# the body scrolls when the window is too short for everything
	var chrome: float = _head.get_combined_minimum_size().y + _foot.get_combined_minimum_size().y + 20.0 + frame.get_minimum_size().y + 12.0
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(120.0, size.y - 2.0 * MARGIN - chrome))
	if list != null:
		_place_list()


# ------------------------------------------------------------------------ refresh --

## What the page shows, in one line: it is redrawn only when it changes.
func _signature() -> String:
	var sig := ""
	for p in sim.people:
		sig += "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s;" % [p.id, jobs.job_of(p), jobs.post_of(p).get("id", ""), p.dead, p.turned, p.away != null, p.downed, hud._doing_person(p), hud._card_word(p), _mood_of(p)[0]]
		for skill in SKILLS:
			sig += "%d," % int(p.skills.get(skill, 0))
	for st in jobs.stations():
		for key in st.settings:
			sig += "%s=%s;" % [key, str(jobs.setting(String(st.id), String(key)))]
	return sig


## Brings the page in line with the game: every row, every station.
func refresh(force: bool = false) -> void:
	if not _open:
		return
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	for p in sim.people:
		_refresh_row(p)
	for st in jobs.stations():
		_refresh_station(st)


## [the word for how they are, its ink]: a mood, or what has become of them.
func _mood_of(p) -> Array:
	var word: String = hud._card_word(p)
	if word != "":
		return [word, hud.SLIP_MARK.danger if word == "Turned" else (INK_AWAY if word == "Away" else hud.PAPER_INK3)]
	var m = hud._mod("morale")
	if m == null or m.get("enabled") == false:
		return ["", hud.PAPER_INK2]
	if hud._breakdown(p):
		return ["Breakdown", hud.SLIP_MARK.danger]
	var mood := String(m.mood(p))
	var ink: Color = MOOD_INK.get(mood, hud.PAPER_INK2)
	if mood == "Breaking":
		ink = hud.SLIP_MARK.danger
	return [mood, ink]


## Whether this person can be given a job or a post: not when they are gone or away.
func can_assign(p) -> bool:
	return not (p.dead or p.turned) and p.away == null


func _refresh_row(p) -> void:
	var r: Dictionary = rows[p.id]
	var gone: bool = p.dead or p.turned
	var open_to_change := can_assign(p)
	# how they are
	var mood := _mood_of(p)
	_set_text(r.mood, String(mood[0]), mood[1])
	r.name.add_theme_color_override("font_color", hud.PAPER_INK3 if gone else hud.PAPER_INK)
	# the day job
	var job_id := String(jobs.job_of(p))
	var st: Dictionary = jobs.station(job_id)
	var job_button: Button = r.job
	if gone:
		_set_text(r.job_text, "–", hud.PAPER_INK3)
		r.job_icon.texture = null
	elif st.is_empty():
		_set_text(r.job_text, "No job", hud.PAPER_INK3)
		r.job_icon.texture = null
	else:
		_set_text(r.job_text, String(st.name), hud.PAPER_INK)
		r.job_icon.texture = hud.icons.get(String(st.get("icon", "")))
	r.job_icon.visible = r.job_icon.texture != null
	job_button.disabled = not open_to_change
	job_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open_to_change else Control.CURSOR_FORBIDDEN
	job_button.tooltip_text = _job_tip(p, st)
	# the night post
	var post: Dictionary = jobs.post_of(p)
	var post_button: Button = r.post
	var post_name := String(post.get("name", "No post"))
	if p.player and jobs.on_patrol(p):
		post_name = "Where you are"    # (the avatar walks by her own hands: the patrol is the crew's)
	_set_text(r.post_text, "–" if gone else post_name, hud.PAPER_INK3 if gone else hud.PAPER_INK)
	r.post_icon.texture = hud.icons.get("moon") if not gone else null
	r.post_icon.visible = r.post_icon.texture != null
	post_button.disabled = not open_to_change
	post_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open_to_change else Control.CURSOR_FORBIDDEN
	post_button.tooltip_text = "Night post for %s: %s\nWhere they hold the wall from the bell until dawn. Click to change it." % [p.first, String(post.get("name", "none"))] if open_to_change else "%s cannot be given a post" % p.first
	if open_to_change and jobs.on_patrol(p):
		post_button.tooltip_text = "%s is on patrol: from the bell (or the call to arms) until dawn they walk the fence line by themselves and go where the dead press.\nClick to give them a post instead (a watchtower, a stretch of fence)." % p.first
	# the skills, the one their station asks for marked
	var asked := "" if gone else String(st.get("skill", ""))
	for skill in SKILLS:
		var cell: PanelContainer = r.skills[skill]
		var marked: bool = String(skill) == asked
		if bool(cell.get_meta("marked")) != marked:
			cell.set_meta("marked", marked)
			cell.add_theme_stylebox_override("panel", _skill_style(marked))
		var number: Label = cell.get_meta("number")
		var value := int(p.skills.get(skill, 0))
		if number.text != str(value):
			number.text = str(value)
		var tip := "%s %d" % [skill, value]
		if marked:
			tip += "\nThe %s asks for it: %s works faster the higher it is" % [String(st.name), p.first]
		cell.tooltip_text = tip
	# what they are doing
	_set_text(r.doing, String(hud._doing_person(p)), hud.PAPER_INK3 if gone else hud.PAPER_INK2)
	r.doing.tooltip_text = r.doing.text


func _job_tip(p, st: Dictionary) -> String:
	if not can_assign(p):
		return "%s cannot be given a job" % p.first
	if st.is_empty():
		return "Day job for %s: none. They %s by day.\nClick to give them one." % [p.first, jobs.no_job_text()]
	return "Day job for %s: %s (%s)\n%s\nClick to change it." % [p.first, String(st.name), String(st.get("where", "")), hud._wrap(String(st.get("blurb", "")))]


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _refresh_station(st: Dictionary) -> void:
	var id := String(st.id)
	var c: Dictionary = station_cards[id]
	var crew: Array = jobs.crew_of(id)
	var names: Array = []
	for i in c.pips.size():
		var pip: Panel = c.pips[i]
		var who = crew[i] if i < crew.size() else null
		pip.set_meta("who", String(who.id) if who != null else "")
		pip.get_meta("pic").texture = hud.portrait_of(who) if who != null else null
		pip.add_theme_stylebox_override("panel", _seat_style(who != null))
		pip.tooltip_text = String(who.name) if who != null else "An empty seat"
	for p in crew:
		names.append(String(p.first))
	_set_text(c.crew, ", ".join(names) if not names.is_empty() else "Nobody", hud.PAPER_INK if not names.is_empty() else hud.PAPER_INK3)
	for key in c.sliders:
		var s: HSlider = c.sliders[key]
		var now := float(jobs.setting(id, key))
		if not is_equal_approx(s.value, now):
			s.set_value_no_signal(now)
		c.values[key].text = _value_text(st.settings[key], now)


# ------------------------------------------------------------------ the marks --

## The place of a station, a night post and/or a person is marked in the world (the overlay draws it): "" for
## nothing of the kind. Called with no arguments, only the stations are marked, faintly (the page is up). With `peek`
## the page fades to show the yard under it (the marks drawn there show through), until the next call.
func show_marks(station: String = "", post: String = "", person: String = "", peek: bool = false) -> void:
	# (a page that is closed marks nothing: the controls it frees still send a last word as they go)
	if not _open:
		return
	var m := {"station": station, "post": post, "person": person}
	_set_peek(peek)
	if m == _marks:
		return
	_marks = m
	hud.set_jobs_hover(m)


## The page and the veil go thin (or come back): at once with reduced motion.
func _set_peek(on: bool) -> void:
	if on == peeking:
		return
	peeking = on
	var page_a := PEEK_PAGE if on else 1.0
	var dim_a := PEEK_DIM if on else DIM
	if _fade != null:
		_fade.kill()
		_fade = null
	if not is_inside_tree() or hud._calm():
		panel.modulate.a = page_a
		_dim.color.a = dim_a
		return
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(panel, "modulate:a", page_a, PEEK_SECONDS)
	_fade.tween_property(_dim, "color:a", dim_a, PEEK_SECONDS)


## What is marked now.
func marks() -> Dictionary:
	return _marks.duplicate()


func _on_row_hover(p, on: bool) -> void:
	rows[p.id].row.add_theme_stylebox_override("panel", _row_style(on))
	if on:
		show_marks(String(jobs.job_of(p)), String(jobs.post_of(p).get("id", "")), String(p.id))
	elif _marks.get("person", "") == String(p.id):
		show_marks()


func _on_station_hover(id: String, on: bool) -> void:
	var c: Dictionary = station_cards[id]
	c.card.add_theme_stylebox_override("panel", _card_style(on))
	if on:
		show_marks(id)
	elif _marks.get("station", "") == id and _marks.get("person", "") == "":
		show_marks()


# ---------------------------------------------------------------------- the lists --

## The day job list for `p`: every station with the seats it has left (a full one is off and says so), then "No job".
func open_job_list(p) -> void:
	if not can_assign(p):
		return
	var entries: Array = []
	var have := String(jobs.job_of(p))
	for st in jobs.stations():
		var id := String(st.id)
		var left: int = jobs.seats_left(id)
		var current := id == have
		var note := "current" if current else ("full" if left <= 0 else "%d left" % left)
		entries.append({"id": id, "icon": String(st.get("icon", "")), "text": String(st.name), "note": note, "disabled": left <= 0 and not current, "current": current,
			"tip": "%s (%s)\n%s" % [String(st.name), String(st.get("where", "")), hud._wrap(String(st.get("blurb", "")))] if left > 0 or current else "No free seat at the %s: %s" % [String(st.name), _names_of(jobs.crew_of(id))]})
	entries.append({"id": "", "icon": "", "text": "No job", "note": "current" if have == "" else "", "disabled": false, "current": have == "", "tip": "No day job: they %s by day" % jobs.no_job_text()})
	_open_list("job", p, rows[p.id].job, "Day job for %s" % p.first, entries)


## The night post list for `p`: the posts on the wall by place; a taken one is greyed with who holds it.
func open_post_list(p) -> void:
	if not can_assign(p):
		return
	var have := String(jobs.post_of(p).get("id", ""))
	var held := _holders()
	var entries: Array = []
	var group := ""
	if jobs.patrol_on():
		# (One House, PATROL: no post to keep: they walk the fence line and go where the dead press; the posts below are the ones the player gives)
		var patrolling: bool = have == jobs.PATROL
		var on_it := _on_patrol_count()
		entries.append({"header": "On the fence line"})
		entries.append({"id": jobs.PATROL, "icon": "moon", "text": "Patrol", "note": ("current · %d" % on_it) if patrolling else ("%d on it" % on_it), "disabled": false, "current": patrolling,
			"tip": "Patrol: walks the fence line by themselves and goes where the dead press, from the bell (or the call to arms) until dawn.\nNo post to keep. A watchtower or a stretch of fence below holds them there instead."})
	for po in jobs.posts():
		var id := String(po.id)
		var g := _post_group(po)
		if g != group:
			group = g
			entries.append({"header": g})
		var who = held.get(id)
		var current := id == have
		var taken: bool = who != null and who != p
		entries.append({"id": id, "icon": "moon", "text": String(po.name), "note": "current" if current else (String(who.first) if taken else ""), "disabled": taken, "current": current,
			"tip": "%s is held by %s" % [String(po.name), String(who.name)] if taken else String(po.name)})
	_open_list("post", p, rows[p.id].post, "Night post for %s" % p.first, entries)


## How many people are on patrol: the living crew whose post is the patrol (the avatar walks by her own hands and is never counted).
func _on_patrol_count() -> int:
	var n := 0
	for q in sim.people:
		if not (q.dead or q.turned or q.player) and jobs.on_patrol(q):
			n += 1
	return n


## Which part of the wall a post is on, for the headings of the list. The posts of the lots that are claimed (round 9: the id of
## a mouth's post is "post_<mouth id>") are grouped under the name of their lot, whatever side of the compound they look at.
func _post_group(po: Dictionary) -> String:
	if String(po.id).begins_with("tower"):
		return "Towers"
	if String(po.get("slot", "")).begins_with("slot_tower_"):
		return "Watchtowers"    # (One House: the base's towers, see `Jobs._post_label`)
	if String(po.id).begins_with("post_") and sim.get("lots") != null:
		var m: Dictionary = sim.lots.mouth(String(po.id).trim_prefix("post_"))
		var lot: Dictionary = sim.lots.lot(String(m.get("lot", "")))
		if not lot.is_empty():
			return String(lot.name)
	var word := "fence" if jobs.patrol_on() else "wall"
	match String(po.get("face", "N")):
		"W":
			return "West " + word
		"E":
			return "East " + word
		"S":
			return "South " + word
	return "North " + word


## post id -> the living person who holds it.
func _holders() -> Dictionary:
	var out := {}
	for q in sim.people:
		if not (q.dead or q.turned) and not jobs.on_patrol(q):    # (patrol is no post: any number of people are on it)
			out[String(jobs.post_of(q).get("id", ""))] = q
	return out


func _names_of(people: Array) -> String:
	var names: Array = []
	for q in people:
		names.append(String(q.first))
	return ", ".join(names)


## Opens a list under `opener`: `entries` are {"id", "icon", "text", "note", "disabled", "current", "tip"} or {"header"}.
func _open_list(kind: String, p, opener: Button, title: String, entries: Array) -> void:
	close_list(false)
	list_kind = kind
	list_for = p
	_list_opener = opener
	# a click anywhere else only closes the list
	_list_catcher = Control.new()
	_list_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_list_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_list_catcher.gui_input.connect(_on_catcher_input)
	add_child(_list_catcher)
	var pop := PanelContainer.new()
	pop.mouse_filter = Control.MOUSE_FILTER_STOP
	pop.add_theme_stylebox_override("panel", _list_style())
	var col: VBoxContainer = hud._vbox(4)
	_list_caption = hud._caps(title, hud.PAPER_INK3)
	col.add_child(_list_caption)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	_list_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(_list_scroll)
	col.add_child(_list_scroll)
	# a gutter at the right for the scroll bar, so that it never sits over the words
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", GUTTER - 4)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_scroll.add_child(gutter)
	_list_box = hud._vbox(2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(_list_box)
	list_items = {}
	var first: Button = null
	var current: Button = null
	for e in entries:
		if e.has("header"):
			var h: Label = hud._caps(String(e.header), hud.PAPER_INK2)
			var hp := MarginContainer.new()
			hp.add_theme_constant_override("margin_top", 4)
			hp.add_theme_constant_override("margin_left", 4)
			hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hp.add_child(h)
			_list_box.add_child(hp)
			continue
		var b := _list_item(e)
		_list_box.add_child(b)
		list_items[String(e.id)] = b
		if first == null and not b.disabled:
			first = b
		if bool(e.current):
			current = b
	# what pointing at a line does (the page fades and the place is marked in the yard)
	_list_hint = hud._label("Point at a job to see its place in the yard" if kind == "job" else "Point at a post to see it in the yard", Fonts.sans(400), 12, hud.PAPER_INK3)
	_list_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_hint.custom_minimum_size.x = 160
	col.add_child(_list_hint)
	pop.add_child(col)
	list = pop
	add_child(pop)
	# the rest of the page is out of the way of the keyboard while the list is open
	Kit.set_focusable(_page, false)
	_place_list()
	_place_list.call_deferred()
	var target: Button = current if current != null and not current.disabled else first
	if target != null:
		_first_focus = true
		target.grab_focus.call_deferred()


func _list_style() -> StyleBox:
	var s: StyleBoxFlat = hud._flat(Dialog.CARD, 5, Color(hud.PAPER_INK, 0.55), true)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 10
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## One line of a list: the picture, the words, and at the right what is to be said about it (seats left, who holds it).
func _list_item(e: Dictionary) -> Button:
	var off: bool = bool(e.get("disabled", false))
	var current: bool = bool(e.get("current", false))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE if off else Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if off else Control.CURSOR_POINTING_HAND
	b.disabled = off
	b.custom_minimum_size = Vector2(0, 30)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, _item_style(state, current))
	b.add_theme_stylebox_override("focus", Kit.focus_box(Dialog.GOLD_EDGE, 4))
	b.tooltip_text = String(e.get("tip", ""))
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	var inner: HBoxContainer = hud._hbox(8)
	var ink: Color = hud.PAPER_INK3 if off else hud.PAPER_INK
	var icon: TextureRect = hud._icon(String(e.get("icon", "")), 16, hud.PAPER_INK3 if off else hud.PAPER_INK2)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.visible = icon.texture != null
	inner.add_child(icon)
	var text: Label = hud._label(String(e.text), Fonts.sans(500), 14, ink)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(text)
	var note := String(e.get("note", ""))
	if note != "":
		var n: Label = hud._label(note, Fonts.cond(700), 13, Dialog.GOLD_INK if current else (hud.PAPER_INK3 if off else hud.PAPER_INK2))
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(n)
	pad.add_child(inner)
	b.add_child(pad)
	var id := String(e.id)
	b.set_meta("id", id)
	b.pressed.connect(_on_pick.bind(id))
	b.mouse_entered.connect(_on_item_hover.bind(id))
	b.focus_entered.connect(_on_item_focus.bind(id))
	return b


func _item_style(state: String, current: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Dialog.CARD_CHOSEN, 0.8) if current else Color(0, 0, 0, 0)
	s.set_corner_radius_all(4)
	match state:
		"hover":
			s.bg_color = Dialog.CARD_CHOSEN
		"pressed":
			s.bg_color = Dialog.CARD_CHOSEN.darkened(0.06)
	if current:
		s.border_color = Dialog.GOLD_EDGE
		s.set_border_width_all(1)
	return s


## Puts the list under its button (above it when there is not room), kept inside the window.
func _place_list() -> void:
	if list == null or _list_opener == null or not is_instance_valid(_list_opener) or not is_inside_tree():
		return
	var open_at: Rect2 = _list_opener.get_global_rect()
	var width := maxf(LIST_W, open_at.size.x)
	list.custom_minimum_size.x = width
	# (its height is worked out here: the container's own is a frame late when the scroll's room has just changed)
	var frame: StyleBox = list.get_theme_stylebox("panel")
	var chrome: float = frame.get_margin(SIDE_TOP) + frame.get_margin(SIDE_BOTTOM) + _list_caption.get_combined_minimum_size().y + _list_hint.get_combined_minimum_size().y + 8.0
	var room := size.y - 16.0 - chrome
	var scroll_h := minf(minf(_list_box.get_combined_minimum_size().y, LIST_MAX_H), maxf(80.0, room))
	_list_scroll.custom_minimum_size.y = scroll_h
	var h := chrome + scroll_h
	var x := clampf(open_at.position.x - global_position.x, 8.0, maxf(8.0, size.x - width - 8.0))
	var below := open_at.end.y - global_position.y + 2.0
	var y := below
	if below + h > size.y - 8.0:
		var above := open_at.position.y - global_position.y - h - 2.0
		y = above if above >= 8.0 else maxf(8.0, size.y - 8.0 - h)
	# (a button that is scrolled out of the page's view still gets its list inside the window)
	y = clampf(y, 8.0, maxf(8.0, size.y - 8.0 - h))
	list.position = Vector2(x, y)
	list.size = Vector2(width, h)


func _on_catcher_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		close_list()
		accept_event()


## Puts the list away (the keyboard goes back to the button it came from).
func close_list(give_back: bool = true) -> void:
	if list == null:
		return
	var opener := _list_opener
	# (hidden at once: what is freed is still in the tree, and under the mouse, till the end of the frame)
	list.hide()
	list.queue_free()
	list = null
	_list_scroll = null
	_list_box = null
	if _list_catcher != null:
		_list_catcher.hide()
		_list_catcher.queue_free()
		_list_catcher = null
	list_items = {}
	list_kind = ""
	list_for = null
	_list_opener = null
	Kit.set_focusable(_page, true)
	show_marks()
	if give_back and opener != null and is_instance_valid(opener) and is_inside_tree() and not opener.disabled:
		opener.grab_focus()


## The keyboard is on a line of the list: the same as the mouse being on it, except that the one it lands on when the list
## opens (the person's own) is only marked: the page does not fade just because a list was opened.
func _on_item_focus(id: String) -> void:
	if _first_focus:
		_first_focus = false
		_mark_item(id, false)
		return
	_mark_item(id, true)


## A place on the list is under the mouse: it is marked in the world, and the page fades to show it.
func _on_item_hover(id: String) -> void:
	_first_focus = false
	_mark_item(id, true)


func _mark_item(id: String, peek: bool) -> void:
	var who := String(list_for.id) if list_for != null else ""
	if list_kind == "post":
		show_marks("", id, who, peek)
	elif id != "":
		show_marks(id, "", who, peek)
	else:
		show_marks("", "", who)


func _on_pick(id: String) -> void:
	var p = list_for
	var kind := list_kind
	close_list()
	if p == null:
		return
	if kind == "job":
		choose_job(p, id)
	else:
		choose_post(p, id)


# --------------------------------------------------------------------- choosing --

## Gives `p` the day job `id` ("" takes them off it). False, and a line at the foot saying why, if they cannot have it.
func choose_job(p, id: String) -> bool:
	error_label.visible = false
	var why := _why_not_job(p, id)
	if why != "":
		_say(why)
		return false
	jobs.assign(p, id)
	refresh()
	hud.ui_sound("ui_click")
	return true


func _why_not_job(p, id: String) -> String:
	if p.dead or p.turned:
		return "%s is gone" % p.first
	if p.away != null:
		return "%s is away" % p.first
	return String(jobs.why_not(p, id)) if id != "" else ""


## Gives `p` the night post `id`. False, and a line at the foot saying who holds it, if it is taken.
func choose_post(p, id: String) -> bool:
	error_label.visible = false
	if p.dead or p.turned:
		_say("%s is gone" % p.first)
		return false
	if p.away != null:
		_say("%s is away" % p.first)
		return false
	var who = _holders().get(id)
	if who != null and who != p:
		_say("%s already holds that post" % who.first)
		return false
	if not jobs.set_post(p, id):
		_say("That post cannot be taken")
		return false
	refresh()
	hud.ui_sound("ui_click")
	return true


func _say(text: String) -> void:
	error_label.text = text.substr(0, 1).to_upper() + text.substr(1) + "."
	error_label.visible = true
	hud.ui_sound("ui_error")


## Auto-assign: everyone off their jobs and the seats filled by skill (the jobs module's own rule).
func auto_assign() -> void:
	error_label.visible = false
	jobs.auto_assign()
	refresh()
	hud.ui_sound("ui_confirm")


## Clear: everyone off their jobs.
func clear_jobs() -> void:
	error_label.visible = false
	jobs.clear()
	refresh()
	hud.ui_sound("ui_click")


# ----------------------------------------------------------------------- closing --

func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	close_list(false)
	_open = false
	set_process_input(false)
	hide()
	closed.emit()
	queue_free()


## The keyboard goes to the first control that can have it (the first person's job button).
func focus_default() -> void:
	if not _open or not is_inside_tree() or list != null:
		return
	var first: Control = null
	for p in sim.people:
		var b: Button = rows[p.id].job
		if not b.disabled and b.is_visible_in_tree():
			first = b
			break
	if first == null:
		first = close_button
	if first != null and first.is_visible_in_tree() and first.focus_mode != Control.FOCUS_NONE:
		first.grab_focus()


## While the page is up every key belongs to it: Esc closes the list and then the screen, J closes the screen,
## Tab, the arrows, Enter and Space go on to the controls (and Tab or an arrow with nothing focused puts the keyboard on
## the first), every other key is not the game's.
func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed:
		return
	var code: Key = ev.keycode
	if ev.echo and (code == KEY_ESCAPE or code == KEY_J):
		# a key that is held down shuts one thing, not the list and then the page
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	if code == KEY_ESCAPE:
		if list != null:
			close_list()
		else:
			close()
	elif code == KEY_J and not ev.ctrl_pressed and not ev.meta_pressed and not ev.alt_pressed:
		close()
	elif code in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and is_inside_tree() and get_viewport().gui_get_focus_owner() == null:
		focus_default()
	elif code in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
