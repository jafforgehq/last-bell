## The radio card: a page of notebook paper over the game. Whoever is at the radio (Ruth, or the
## best leader who is up) has news: the title, what came in, and the ways to answer, each with its
## cost and risk written under it. Keys 1 to 3 answer, Tab and the arrows move between the answers
## and Enter takes the one that has the keyboard; Esc puts the answer off (the card stays pending,
## the rules go on, and the radio alert opens it again; left alone it takes its default after two
## game hours). A card with no choice has happened already and has one button: Understood.
##
## It reads everything from the storyteller (`sim.storyteller.pending()`), and answers through
## `sim.storyteller.choose(i)`. It borrows the HUD's styles, colours and icons (the `hud` it is given)
## so it looks like the rest. The ink on the page is the HUD's PAPER_INK family. Opened by
## story_ui.gd, which also pauses the rules while it is up and puts the speed back after.
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")

## Emitted once, when the card is gone: `answered` is false when it was only put off.
signal closed(answered: bool)

## The page is at most this wide (and never wider than the window less a margin); in a window
## narrower than NARROW_W it takes all the room there is, so the words wrap less and the page is
## shorter. GUTTER is the room kept at the right of the words for the scroll bar.
const MAX_W := 540.0
const NARROW_W := 900.0
const GUTTER := 14
const ICON_PATH := "res://assets/ui/icons/radio.png"
const PORTRAIT_PX := 48
## The keys of the answers.
const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const PAD_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]

var hud
var sim
## The card as `pending()` said when the page was made.
var card := {}
var panel: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var title_label: Label
var text_label: Label
var head: Control
var foot: Control
var error_label: Label
## One button for each way to answer, in order (a card with no choice has none: see done_button).
var choice_buttons: Array = []
var done_button: Button = null
var later_button: Button = null
var _open := true


func setup(h, s) -> void:
	hud = h
	sim = s
	card = sim.storyteller.pending()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# a page over the whole window: the HUD knows it as a modal (the speech bubbles keep quiet under it)
	set_meta("modal", true)
	_build()
	resized.connect(_layout)
	_layout()
	# wrapped text only knows its height once it has a width: lay out again a frame on
	_layout.call_deferred()


# ------------------------------------------------------------------------- build --

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.035, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = hud._panel(hud._paper_style())
	center.add_child(panel)
	var col: VBoxContainer = hud._vbox(10)
	panel.add_child(col)

	head = _build_head()
	col.add_child(head)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(scroll)
	col.add_child(scroll)
	# a gutter at the right for the scroll bar, so that it never sits over the words
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", GUTTER)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gutter)
	body = hud._vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(body)

	title_label = hud._label(String(card.get("title", "")), Fonts.cond(700), 28, hud.PAPER_INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 200
	body.add_child(title_label)
	text_label = hud._label(String(card.get("text", "")), Fonts.sans(400), 16, hud.PAPER_INK)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size.x = 200
	body.add_child(text_label)
	if bool(card.get("resolved", false)):
		_build_outcome()
	else:
		_build_choices()
	col.add_child(_build_foot())


## Who is at the radio: their portrait, their name and the little radio.
func _build_head() -> Control:
	var row: HBoxContainer = hud._hbox(10)
	var who = _speaker()
	if who != null and hud.portrait_of(who) != null:
		var pic := TextureRect.new()
		pic.texture = hud.portrait_of(who)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var words: VBoxContainer = hud._vbox(0)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(hud._caps("On the radio", hud.PAPER_INK3))
	var name_text: String = who.name if who != null else String(card.get("speaker", "The radio"))
	var name_label: Label = hud._label(name_text, Fonts.cond(700), 20, hud.PAPER_INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(name_label)
	row.add_child(words)
	var icon: TextureRect = hud._icon("radio", 30, hud.PAPER_INK2)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon.texture == null:
		icon.texture = _icon_texture()
	row.add_child(icon)
	return row


## The person at the radio, or null (the card names them by id).
func _speaker():
	var id := String(card.get("speaker_id", ""))
	for p in sim.people:
		if p.id == id:
			return p
	return null


## The radio's picture, for a HUD whose icons do not have it (it is not one of the baked ones).
func _icon_texture() -> Texture2D:
	if ResourceLoader.exists(ICON_PATH):
		var t = load(ICON_PATH)
		if t is Texture2D:
			return t
	if FileAccess.file_exists(ICON_PATH):
		var img := Image.load_from_file(ProjectSettings.globalize_path(ICON_PATH))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## What came of a card that has happened already: what it did, line by line.
func _build_outcome() -> void:
	var lines: Array = card.get("changes", [])
	var said := String(card.get("result", ""))
	if said == "" and lines.is_empty():
		return
	body.add_child(_rule())
	if said != "":
		var l: Label = hud._label(said, Fonts.sans(500), 15, hud.PAPER_INK2)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 200
		body.add_child(l)
	for line in lines:
		var row: HBoxContainer = hud._hbox(8)
		row.add_child(hud._label("•", Fonts.cond(700), 17, hud.PAPER_INK2))
		var t: Label = hud._label(String(line), Fonts.cond(600), 17, hud.PAPER_INK)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size.x = 160
		row.add_child(t)
		body.add_child(row)


## The answers: a key chip, a button and under it the cost and the risk, in plain words.
func _build_choices() -> void:
	body.add_child(_rule())
	var choices: Array = card.get("choices", [])
	for i in choices.size():
		var c: Dictionary = choices[i]
		var enabled: bool = bool(c.get("enabled", true))
		var row: HBoxContainer = hud._hbox(10)
		var chip: PanelContainer = hud._kbd(str(i + 1))
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		# every key chip the same width, so that the buttons line up
		chip.custom_minimum_size.x = 24
		var chip_pad := MarginContainer.new()
		chip_pad.add_theme_constant_override("margin_top", 11)
		chip_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_pad.add_child(chip)
		row.add_child(chip_pad)
		var col: VBoxContainer = hud._vbox(3)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b: Button = hud._button(String(c.get("label", "")), false, true)
		b.focus_mode = Control.FOCUS_ALL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_FORBIDDEN
		b.add_theme_stylebox_override("focus", Kit.focus_box(hud.ACCENT))
		b.disabled = not enabled
		b.pressed.connect(_choose.bind(i))
		b.set_meta("index", i)
		col.add_child(b)
		var hint := String(c.get("hint", ""))
		if hint != "":
			var h: Label = hud._label(hint, Fonts.sans(400), 13, hud.PAPER_INK2)
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.custom_minimum_size.x = 160
			col.add_child(h)
		if not enabled:
			var why: Label = hud._label(String(c.get("why", "")), Fonts.sans(600), 13, hud.SLIP_MARK.danger)
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(why)
		row.add_child(col)
		body.add_child(row)
		choice_buttons.append(b)


## The foot: what happens if nobody answers, and Decide later; or just Understood.
func _build_foot() -> Control:
	var wrap: VBoxContainer = hud._vbox(6)
	error_label = hud._label("", Fonts.sans(600), 13, hud.SLIP_MARK.danger)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	wrap.add_child(error_label)
	var row: HBoxContainer = hud._hbox(10)
	var note := ""
	if bool(card.get("resolved", false)):
		done_button = hud._button("Understood", true, true)
		done_button.focus_mode = Control.FOCUS_ALL
		done_button.add_theme_stylebox_override("focus", Kit.focus_box(hud.INK))
		done_button.pressed.connect(_choose.bind(0))
		var spacer: Control = hud._spacer()
		row.add_child(spacer)
		row.add_child(done_button)
	else:
		var default_i := int(card.get("bot", 0))
		var choices: Array = card.get("choices", [])
		if default_i >= 0 and default_i < choices.size():
			note = "If nobody answers by %s: %s." % [_clock_text(float(card.get("until", 0.0))), String(choices[default_i].label)]
		var n: Label = hud._label(note, Fonts.sans(400), 12, hud.PAPER_INK3)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.custom_minimum_size.x = 120
		row.add_child(n)
		later_button = hud._button("Decide later", false, true)
		later_button.focus_mode = Control.FOCUS_ALL
		later_button.add_theme_stylebox_override("focus", Kit.focus_box(hud.ACCENT))
		later_button.tooltip_text = "Put it off: the rules go on, and the radio alert brings the card back\nKey: Esc"
		later_button.pressed.connect(_put_off)
		row.add_child(later_button)
	wrap.add_child(row)
	foot = wrap
	return wrap


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = hud.PAPER_LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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


## 14.5 as "14:30".
func _clock_text(hour: float) -> String:
	var m := roundi(fposmod(hour * 60.0, 1440.0))
	return "%02d:%02d" % [floori(m / 60.0), m % 60]


# ------------------------------------------------------------------------ layout --

func _layout() -> void:
	if panel == null or not is_inside_tree():
		return
	panel.custom_minimum_size.x = maxf(minf(size.x - 32.0, MAX_W if size.x >= NARROW_W else size.x), 0.0)
	# the body scrolls when the window is too short for everything
	var frame: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	var chrome: float = head.get_combined_minimum_size().y + foot.get_combined_minimum_size().y + 20.0 + frame.y + 12.0
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(96.0, size.y - 32.0 - chrome))


# ----------------------------------------------------------------------- answering --

## Answer `i`: the storyteller carries it out; the card goes if it could be.
func _choose(i: int) -> void:
	if not _open:
		return
	if sim.storyteller.choose(i):
		_close(true)
		return
	if sim.storyteller.pending().is_empty():
		_close(true)
		return
	error_label.text = "That cannot be done just now."
	error_label.visible = true


## Esc: the card is put away and the answer left for later (a card that has happened already is
## simply read).
func _put_off() -> void:
	if not _open:
		return
	if bool(card.get("resolved", false)):
		_choose(0)
		return
	_close(false)


## The 1-based number of a key (1 to 9), or -1.
static func number_of(code: Key) -> int:
	var i := NUMBER_KEYS.find(code)
	if i >= 0:
		return i
	return PAD_KEYS.find(code)


func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed:
		return
	var code: Key = ev.keycode
	if code == KEY_ESCAPE:
		_put_off()
	elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		_activate()
	elif code == KEY_TAB:
		_move_focus(-1 if ev.shift_pressed else 1)
	elif code == KEY_DOWN or code == KEY_RIGHT:
		_move_focus(1)
	elif code == KEY_UP or code == KEY_LEFT:
		_move_focus(-1)
	else:
		var i := number_of(code)
		if i >= 0 and i < choice_buttons.size() and not choice_buttons[i].disabled:
			_choose(i)
		elif i == 0 and done_button != null:
			_choose(0)
	# while the card is up every key belongs to it: the game does not see them
	if is_inside_tree():
		get_viewport().set_input_as_handled()


## Enter: the answer that has the keyboard; with none, Understood, or the keyboard goes to the first.
func _activate() -> void:
	var owner = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner is Button and (choice_buttons.has(owner) or owner == done_button or owner == later_button) and not owner.disabled:
		owner.pressed.emit()
		return
	if done_button != null:
		done_button.pressed.emit()
		return
	_move_focus(1)


## Tab and the arrows go round the answers (and Decide later).
func _move_focus(step: int) -> void:
	var ring: Array = []
	for b in choice_buttons:
		if not b.disabled:
			ring.append(b)
	if later_button != null:
		ring.append(later_button)
	if done_button != null:
		ring.append(done_button)
	if ring.is_empty() or not is_inside_tree():
		return
	var owner = get_viewport().gui_get_focus_owner()
	var at := ring.find(owner)
	var next: Button = ring[0] if at < 0 and step > 0 else (ring[ring.size() - 1] if at < 0 else ring[posmod(at + step, ring.size())])
	next.grab_focus()


func is_open() -> bool:
	return _open


## The page is taken away without an answer (the run is over).
func put_away() -> void:
	_close(false)


func _process(_dt: float) -> void:
	# the card was settled from outside (a test, a load): this page has nothing left to ask
	if _open and sim != null and sim.storyteller.pending().is_empty():
		_close(true)


func _close(answered: bool) -> void:
	if not _open:
		return
	_open = false
	set_process_input(false)
	set_process(false)
	hide()
	closed.emit(answered)
	queue_free()
