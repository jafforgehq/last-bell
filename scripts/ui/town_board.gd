## The Town Board (round 8): the page the settlement game plans its trips on, in place of the old four-site
## scavenging dialog (which still serves the classic start). A map of the town drawn on noticeboard paper
## (scripts/ui/town_map.gd) with a pin for each known place and a faint "?" for each place nobody has seen; the card
## of the place that is chosen; the party picker; the six things a party can do; and, at the foot, the parties that
## are out and when they are due.
##
##   - Pick a place by clicking its pin, or with the keyboard (Tab and the arrows go between the pins, Enter or Space
##     picks one). The card says what the place is, how dangerous, how long the trip takes (and "back tomorrow" when it
##     would run past dusk: a night out, without the wall), what it is likely to give, what has been done to it (picked
##     over, raided), the nest that sends the dead from there, whether someone is hiding there, what an outpost would
##     yield and cost, and who holds it.
##   - The party is one to three people who are free to go, as in the old dialog: the leader first (the one selected
##     when the page was opened, or the first who is free), the others on a click. A lone scavenger brings back less and
##     a leader finds more; the page says so.
##   - Round 13: when the colony has a parked vehicle there is a row (under the map's key on a wide page, under the people
##     on a narrow one), "On foot" or one chip for each parked vehicle (its name, its seats, the fuel the trip to the chosen place burns, the trip's hours by it). The
##     vehicle that is chosen sets the size of the party (its seats, in place of three) and the trip's hours, and goes
##     with Go, Scout and Clear; what the rules refuse (the fuel, the seats, a place too far to walk to) is told on the
##     buttons as the other reasons are. A place that only a vehicle reaches has a tag, and one that holds a vehicle says so.
##   - Go searches the place for loot. Scout looks the way over (no loot: it shows the places near). Clear turns the
##     dead out of the place (a nest needs two; the chance is told in words from the party's Shooting against the
##     place's danger, as the rules throw it). Claim makes a cleared place with an outpost yours, for scrap. Garrison
##     leaves the party there until Recall. A button that cannot be pressed says why, on the button's tooltip and in
##     a line under the buttons; none is hidden for being off (Claim only shows for a place that has an outpost to
##     claim, Garrison and Recall for an outpost).
##   - Go, Scout and Clear send the party through the gate and close the page; Claim, Garrison and Recall are done at
##     once and the page stays, and says what was done.
##
## Opened by hud.open_scavenge in a game with a board (`sim.town.on`); the rules wait while it is up and the speed comes
## back when it is closed. It follows the game (`refresh`, when the HUD is updated). Esc or G closes it. Everything is
## read from the scavenging module (can_send, why_not, why_not_action, action_hours, available_sites, free_survivors,
## parties, send) and the town (claim, garrison_send, recall, roads), and changed through them.
##
## It borrows the HUD's styles, colours and icons (the `hud` it is given) so it looks like the Jobs and Build screens:
## the ink on the page is the HUD's PAPER_INK family (the chalk colours are for the boards).
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const Map := preload("res://scripts/ui/town_map.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const CrewLoad := preload("res://scripts/sim/crew_load.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")

## Emitted once, when the page is gone (a party sent, or closed).
signal closed

## The page is at most this wide and keeps MARGIN from the window's edge; from WIDE_W the map and the card sit
## side by side, under it the card goes below the map.
const MAX_W := 1200.0
const WIDE_W := 900.0
const MARGIN := 12.0
## The room kept at the right of the words for the scroll bar.
const GUTTER := 14
## The card's column when it is beside the map (a share of the page between the two), and the gap between them.
const DETAIL_MIN_W := 320.0
const DETAIL_MAX_W := 400.0
const COLUMN_GAP := 18.0
## The map is never narrower than this.
const MAP_MIN_W := 360.0
## A person's chip in the party picker, and a button of the page.
const CHIP_W := 120.0
const CHIP_H := 60.0
const BUTTON_H := 38.0
const BUTTON_W := 92.0
## The veil over the game.
const DIM := 0.62
## The chance of clearing a place, as words: at or over LIKELY_AT it is "likely", at or over RISK_AT "a risk", else
## "unlikely". (The chance itself is the rules': scavenge.gd's `_decide_town`.)
const LIKELY_AT := 0.65
const RISK_AT := 0.4
## The ink of the lines that say why a button is off: a deeper amber than the slips' (4.5:1 on the darkest of the page).
const WHY_INK := Color("#74400a")
## What Go says in a game with an avatar: it sends the others, without the player.
const AVATAR_GO_TIP := "Send them without you: worse loot, no rescues"
## The words for a place's danger (0 to 3).
const DANGER_WORDS := ["Quiet", "A few of the dead about", "The dead are thick here", "Overrun"]
## The hours of the day a party can set off (the rules' own), and the hour the day ends (dusk).
const DUSK_H := 19.0
const FIRST_LIGHT_H := 6.5
const LEAVE_BY_H := 10.0
## The party's tags and the effects of the party on a trip.
const ACTION_WORDS := {"loot": "looting", "scout": "scouting", "clear": "clearing"}
## What a place may give, in the order its chips are shown: the stocks, and the fuel of round 13.
const LOOT_ORDER := ["food", "water", "scrap", "ammo", "meds", "fuel"]
const LOOT_NAME := {"food": "Food", "water": "Water", "scrap": "Scrap", "ammo": "Ammo", "meds": "Medicine", "fuel": "Fuel"}
## A vehicle's chip in the picker: its size.
const RIDE_W := 168.0
const RIDE_H := 62.0

var hud
var sim
var town
var scav
## The people going (Person objects), the leader first. With an avatar (round 17) these are the OTHERS: the player always goes and
## leads a trip they play, so they are not in the list but the first of the party row (`me_chip`), and the limit counts them.
var party: Array = []
## The place that is chosen ("" until one is).
var site_id := ""
## The vehicle the party goes in (the id of one of the fleet that is parked), or "" on foot.
var vehicle_id := ""
## id -> the places as the board offers them (scavenge.available_sites: the known ones).
var sites := {}

var panel: PanelContainer
var scroll: ScrollContainer
var body: BoxContainer
var map: Control
var map_col: VBoxContainer
var detail_col: VBoxContainer
var legend: Control
var card: PanelContainer
var party_box: VBoxContainer
var chip_flow: HFlowContainer
## Round 16: under the party, what the trip leaves empty at home and how many hold the yard (informs, never stops Go).
var leave_label: Label
var out_box: HFlowContainer
var out_caption: Label
## The foot, which never scrolls (Go is always in reach): at the left the parties that are out and the keys; at the right,
## under the card when it is beside the map, the buttons with the lines that say why those that are off are off, and
## Close. A narrow page has the parties out at the end of its body instead, and no keys line.
var foot_body: BoxContainer
var foot_left: VBoxContainer
var foot_right: VBoxContainer
var out_section: VBoxContainer
var actions_block: VBoxContainer
var _arranged_wide := true
var _avatar_buttons := false
var go_button: Button
var play_button: Button
var scout_button: Button
var clear_button: Button
var claim_button: Button
var garrison_button: Button
var recall_button: Button
var close_button: Button
var error_label: Label
var hint_label: Label
## Under the buttons: why each that is off is off.
var why_box: VBoxContainer
## The card's parts: see _build_card.
var empty_label: Label
var place_view: VBoxContainer
var name_label: Label
var thumb: TextureRect
var tag_flow: HFlowContainer
var blurb_label: Label
var facts := {}
var pip_row: HBoxContainer
var chips_box: HFlowContainer
## The row of the picker for the vehicles (round 13): shown only while one is parked; "" -> the "On foot" chip, a
## vehicle's id -> its chip.
var ride_box: VBoxContainer
var ride_flow: HFlowContainer
var ride_tip: Label
var ride_chips := {}
var _ride_sig := ""
## person id -> {"chip": Button, "person": Person, "lead": Control (the star of the one who leads)}
var chips := {}
## The player's own chip, first in the row of an avatar game ("You lead": it is not a choice), or null.
var me_chip: Button = null
## action -> its button. The lines under the buttons say why those that are off are off, those with the same
## reason together (`why_lines` are the labels, `_why_of` the line that covers each action).
var buttons := {}
var why_lines: Array = []
var _why_of := {}
var _head: Control
var _foot: Control
var _tip_label: Label
var _effect_label: Label
## party number -> the clock when this page first saw it leave (the rules do not keep the hour a party set off)
var _departures := {}
var _note_label: Label
var _note := ""
var _open := true
var _sig := ""
var _routes := {}
var _free_sig := ""
var _out_sig := ""


## `sel` is the selected Person, or null: the page picks who leads if they cannot go.
func setup(h, s, sel) -> void:
	hud = h
	sim = s
	town = sim.town
	scav = sim.scavenge
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# a page over the whole window: the HUD knows it as a modal (the speech bubbles keep quiet under it)
	set_meta("modal", true)
	var free_people: Array = scav.free_survivors()
	if sel != null and free_people.has(sel):
		party = [sel]
	elif not free_people.is_empty():
		party = [free_people[0]]
		if sel != null and sel != avatar():
			_note = "%s can't go out now." % sel.first
	_build()
	refresh(true)
	resized.connect(_layout)
	body.minimum_size_changed.connect(func(): _layout.call_deferred())
	_foot.minimum_size_changed.connect(func(): _layout.call_deferred())
	_head.minimum_size_changed.connect(func(): _layout.call_deferred())
	_layout()
	_layout.call_deferred()
	set_process(false)


# ------------------------------------------------------------------- build --

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.035, DIM)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = hud._panel(hud._paper_style())
	center.add_child(panel)
	var col: VBoxContainer = hud._vbox(8)
	panel.add_child(col)

	# the title, and beside it (under it when there is no room) what the page is for
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 14)
	head.add_theme_constant_override("v_separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hud._label("The Town Board", Fonts.cond(700), 26, hud.PAPER_INK))
	var sub: Label = hud._caps("Pick a place on the map, then who goes", hud.PAPER_INK2)
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
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", GUTTER)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gutter)
	body = BoxContainer.new()
	body.add_theme_constant_override("separation", int(COLUMN_GAP))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gutter.add_child(body)

	# the map and its key
	map_col = hud._vbox(6)
	map = Map.new()
	map.setup(hud)
	map.custom_minimum_size = Vector2(MAP_MIN_W, MAP_MIN_W * 0.7)
	map.place_chosen.connect(_on_pin_chosen)
	map_col.add_child(map)
	legend = Map.make_legend(hud, hud.PAPER_INK2)
	map_col.add_child(legend)
	body.add_child(map_col)

	# the place and the party
	detail_col = hud._vbox(10)
	detail_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card = _build_card()
	detail_col.add_child(card)
	detail_col.add_child(_build_party())
	body.add_child(detail_col)
	# the ride is under the map's key while the page is wide (the left column has the room), under the people when it is narrow
	_reparent(ride_box, map_col)

	# the foot, which never scrolls
	var foot: VBoxContainer = hud._vbox(6)
	foot.add_child(_rule())
	foot_body = BoxContainer.new()
	foot_body.add_theme_constant_override("separation", int(COLUMN_GAP))
	foot_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot_left = hud._vbox(4)
	foot_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_section = hud._vbox(4)
	out_caption = hud._caps("Out now", hud.PAPER_INK2)
	out_section.add_child(out_caption)
	out_box = HFlowContainer.new()
	out_box.add_theme_constant_override("h_separation", 8)
	out_box.add_theme_constant_override("v_separation", 4)
	out_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out_section.add_child(out_box)
	foot_left.add_child(out_section)
	hint_label = _para(12, hud.PAPER_INK3)
	hint_label.text = "Arrows and Tab go between the pins, Enter picks one. G or Esc closes."
	foot_left.add_child(hint_label)
	foot_body.add_child(foot_left)
	foot_right = hud._vbox(6)
	actions_block = hud._vbox(6)
	actions_block.add_child(_build_actions())
	error_label = _para(13, hud.SLIP_MARK.danger, 600)
	error_label.visible = false
	actions_block.add_child(error_label)
	why_box = hud._vbox(2)
	for i in 6:
		var l := _para(13, WHY_INK, 600)
		l.visible = false
		why_box.add_child(l)
		why_lines.append(l)
	actions_block.add_child(why_box)
	foot_right.add_child(actions_block)
	var row: HBoxContainer = hud._hbox(10)
	row.add_child(_spacer())
	close_button = _button("Close", false)
	close_button.tooltip_text = "Close the Town Board\nKey: G"
	close_button.pressed.connect(close)
	row.add_child(close_button)
	foot_right.add_child(row)
	foot_body.add_child(foot_right)
	foot.add_child(foot_body)
	_foot = foot
	col.add_child(foot)


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


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


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = hud.PAPER_LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A wrapped line of the page: it asks for a little width so that it never folds into a column of letters.
func _para(size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = hud._label("", Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


## A button of the HUD's kind on a page that the keyboard can reach (the HUD's own never take focus).
func _button(text: String, primary: bool = false) -> Button:
	var b: Button = hud._button(text, primary, true)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("focus", Kit.focus_box(hud.INK if primary else hud.ACCENT))
	return b


## A card of the page: a sheet a little lighter than the paper with a thin ink edge.
func _card_style() -> StyleBox:
	var s: StyleBoxFlat = hud._flat(Dialog.CARD, 4, Color(hud.PAPER_INK, 0.3), false)
	s.set_border_width_all(1)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 9
	s.content_margin_bottom = 10
	return s


## A small tag in capitals: ink on a faint wash of ink, a pill.
func _tag(text: String, ink: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var chip := PanelContainer.new()
	var s := StyleBoxFlat.new()
	var color: Color = ink if ink.a > 0.0 else hud.PAPER_INK2
	s.bg_color = Color(color, 0.1)
	s.border_color = Color(color, 0.4)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", s)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(hud._caps(text, color))
	return chip


## The card of the chosen place: made once, and shown and filled as the choice changes.
func _build_card() -> PanelContainer:
	var c: PanelContainer = hud._panel(_card_style())
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	var col: VBoxContainer = hud._vbox(7)
	empty_label = _para(14, hud.PAPER_INK2)
	empty_label.text = "Nothing is chosen. Click a pin on the map to see the place, what it is likely to give and what it would take."
	col.add_child(empty_label)

	place_view = hud._vbox(7)
	var head: HBoxContainer = hud._hbox(10)
	thumb = TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.custom_minimum_size = Vector2(80, 46)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.visible = false
	head.add_child(thumb)
	var title: VBoxContainer = hud._vbox(3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = hud._label("", Fonts.cond(700), 22, hud.PAPER_INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 120
	title.add_child(name_label)
	tag_flow = HFlowContainer.new()
	tag_flow.add_theme_constant_override("h_separation", 6)
	tag_flow.add_theme_constant_override("v_separation", 3)
	tag_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(tag_flow)
	head.add_child(title)
	place_view.add_child(head)
	blurb_label = _para(13, hud.PAPER_INK2)
	place_view.add_child(blurb_label)
	place_view.add_child(_rule())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# danger: pips and the words
	var danger_value: HBoxContainer = hud._hbox(8)
	pip_row = hud._hbox(4)
	pip_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 3:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(10, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
	danger_value.add_child(pip_row)
	var danger_words := _para(13, hud.PAPER_INK)
	danger_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	danger_value.add_child(danger_words)
	_fact(grid, "danger", "Danger", danger_value, danger_words)
	_fact(grid, "trip", "Trip", _para(13, hud.PAPER_INK))
	_fact(grid, "vehicle", "Vehicle", _para(13, hud.PAPER_INK))
	# what it is likely to give: the hint and what each stock is worth
	var loot_box: VBoxContainer = hud._vbox(3)
	var loot_hint := _para(13, hud.PAPER_INK)
	loot_box.add_child(loot_hint)
	chips_box = HFlowContainer.new()
	chips_box.add_theme_constant_override("h_separation", 10)
	chips_box.add_theme_constant_override("v_separation", 3)
	chips_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loot_box.add_child(chips_box)
	_fact(grid, "loot", "Likely", loot_box, loot_hint)
	_fact(grid, "note", "Now", _para(13, WHY_INK, 600))
	_fact(grid, "nest", "Nest", _para(13, hud.PAPER_INK))
	_fact(grid, "hiding", "Hiding", _para(13, hud.PAPER_INK))
	_fact(grid, "outpost", "Outpost", _para(13, hud.PAPER_INK))
	_fact(grid, "held", "Held by", _para(13, hud.PAPER_INK))
	_fact(grid, "clear", "Clearing", _para(13, hud.PAPER_INK))
	place_view.add_child(grid)
	col.add_child(place_view)
	c.add_child(col)
	return c


## One line of the card's grid: a caption and what it says (`value` is what goes in the grid; `label` is the label
## that carries the words, when that is not `value` itself).
func _fact(grid: GridContainer, key: String, caption: String, value: Control, label: Label = null) -> void:
	var cap: Label = hud._caps(caption, hud.PAPER_INK2)
	cap.custom_minimum_size.x = 66
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_child(cap)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	facts[key] = {"cap": cap, "value": value, "label": label if label != null else value}


## The party picker: the people who can go, the leader first; what the party will be like on the road.
func _build_party() -> VBoxContainer:
	party_box = hud._vbox(6)
	var caption := HFlowContainer.new()
	caption.add_theme_constant_override("h_separation", 10)
	caption.add_theme_constant_override("v_separation", 0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_child(hud._caps("Party", hud.PAPER_INK2))
	_tip_label = hud._label("", Fonts.sans(400), 12, hud.PAPER_INK3)
	_tip_label.size_flags_vertical = Control.SIZE_SHRINK_END
	caption.add_child(_tip_label)
	party_box.add_child(caption)
	chip_flow = HFlowContainer.new()
	chip_flow.add_theme_constant_override("h_separation", 8)
	chip_flow.add_theme_constant_override("v_separation", 6)
	chip_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	party_box.add_child(chip_flow)
	# the ride: on foot, or in one of the vehicles that are parked (only there when one is)
	ride_box = hud._vbox(6)
	var ride_caption := HFlowContainer.new()
	ride_caption.add_theme_constant_override("h_separation", 10)
	ride_caption.add_theme_constant_override("v_separation", 0)
	ride_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ride_caption.add_child(hud._caps("Ride", hud.PAPER_INK2))
	ride_tip = hud._label("", Fonts.sans(400), 12, hud.PAPER_INK3)
	ride_tip.size_flags_vertical = Control.SIZE_SHRINK_END
	ride_caption.add_child(ride_tip)
	ride_box.add_child(ride_caption)
	ride_flow = HFlowContainer.new()
	ride_flow.add_theme_constant_override("h_separation", 8)
	ride_flow.add_theme_constant_override("v_separation", 6)
	ride_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ride_box.add_child(ride_flow)
	ride_box.visible = false
	party_box.add_child(ride_box)
	_note_label = _para(13, WHY_INK)
	_note_label.visible = false
	party_box.add_child(_note_label)
	_effect_label = _para(13, hud.PAPER_INK)
	party_box.add_child(_effect_label)
	leave_label = _para(13, WHY_INK)
	leave_label.visible = false
	party_box.add_child(leave_label)
	return party_box


## The six buttons (the reasons of those that are off go under them, in the foot).
func _build_actions() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var defs := [["loot", "Go", true], ["play", "Take control", false], ["scout", "Scout", false], ["clear", "Clear", false], ["claim", "Claim", false], ["garrison", "Garrison", false], ["recall", "Recall", false]]
	for d in defs:
		var b := _button(String(d[1]), bool(d[2]))
		b.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
		b.pressed.connect(act.bind(String(d[0])))
		b.set_meta("action", String(d[0]))
		flow.add_child(b)
		buttons[String(d[0])] = b
	go_button = buttons.loot
	play_button = buttons.play
	scout_button = buttons.scout
	clear_button = buttons.clear
	claim_button = buttons.claim
	garrison_button = buttons.garrison
	recall_button = buttons.recall
	return flow


# ------------------------------------------------------------------- layout --

func _layout() -> void:
	if panel == null or not is_inside_tree():
		return
	var pw := minf(size.x - 2.0 * MARGIN, MAX_W)
	panel.custom_minimum_size.x = maxf(pw, 0.0)
	var frame: StyleBox = panel.get_theme_stylebox("panel")
	var inner := pw - frame.get_margin(SIDE_LEFT) - frame.get_margin(SIDE_RIGHT) - float(GUTTER)
	var wide := pw >= WIDE_W
	body.vertical = not wide
	foot_body.vertical = not wide
	_arrange(wide)
	var chrome: float = _head.get_combined_minimum_size().y + _foot.get_combined_minimum_size().y + frame.get_minimum_size().y + 16.0
	var room := maxf(120.0, size.y - 2.0 * MARGIN - chrome)
	var below: float = legend.get_combined_minimum_size().y + 6.0
	var map_w: float
	if wide:
		var detail_w := clampf(inner * 0.33, DETAIL_MIN_W, DETAIL_MAX_W)
		var room_w := inner - COLUMN_GAP - detail_w
		map_w = room_w
		# the whole map in view, with its key and the ride under it, if the window is tall enough for that (the ride wraps
		# by the map's width, so it is asked again with the width the map came to)
		for _i in 2:
			var under := below + ((_ride_height(map_w) + 6.0) if ride_box.visible else 0.0)
			map_w = minf(room_w, map.width_for_height(room - under))
		detail_col.custom_minimum_size.x = detail_w
		detail_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# the buttons are under the card, at the right of the foot
		foot_right.custom_minimum_size.x = detail_w
		foot_right.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		# the card goes under the map: the map takes about half the room, so that the card is not far down
		map_w = minf(inner, map.width_for_height(0.55 * room - below))
		detail_col.custom_minimum_size.x = 0.0
		detail_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot_right.custom_minimum_size.x = 0.0
		foot_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# (a narrow page lets the key use the whole width, and centres the map over it)
	map_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if wide else Control.SIZE_EXPAND_FILL
	map.size_flags_horizontal = Control.SIZE_FILL if wide else Control.SIZE_SHRINK_CENTER
	map_w = maxf(map_w, MAP_MIN_W)
	# the pins keep apart: a wide town (the city across the river) gets the width it needs, and the page scrolls
	map_w = maxf(map_w, minf(map.width_for_clear_pins(), maxf(inner, 200.0)))
	map_w = minf(map_w, maxf(inner, 200.0))
	map.custom_minimum_size = Vector2(map_w, map.height_for_width(map_w))
	map_col.custom_minimum_size.x = map_w if wide else 0.0
	# the body scrolls when the window is too short for everything
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, room)


## How tall the ride row is when it is `width` wide: its caption, and its chips in as many rows as the width needs.
func _ride_height(width: float) -> float:
	var n := maxi(ride_chips.size(), 1)
	var per_row := maxi(1, int(floorf((width + 8.0) / (RIDE_W + 8.0))))
	var rows := ceili(float(n) / float(per_row))
	return 22.0 + 6.0 + float(rows) * RIDE_H + float(rows - 1) * 6.0


## Puts the parties out where this width wants them: in the foot's left half (with the keys), or at the end of the body
## (a narrow page has no left half).
func _arrange(wide: bool) -> void:
	if wide == _arranged_wide:
		return
	_arranged_wide = wide
	_reparent(out_section, foot_left if wide else body)
	if wide:
		_reparent(ride_box, map_col)
	else:
		_reparent(ride_box, party_box, chip_flow.get_index() + 1)
	if wide:
		foot_left.move_child(out_section, 0)
	foot_left.visible = wide


func _reparent(node: Control, parent: Node, at: int = -1) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node)
	if at >= 0:
		parent.move_child(node, at)


# ----------------------------------------------------------------- the choices --

## Chooses a place (a known one): its pin is ringed in gold and the card shows it. False if it is not known.
func select_place(id: String) -> bool:
	if not sites.has(id):
		return false
	var changed := id != site_id
	site_id = id
	error_label.visible = false
	refresh(true)
	if changed:
		hud.ui_sound("ui_click")
	return true


func _on_pin_chosen(id: String) -> void:
	select_place(id)
	# under the map (a narrow window) the card is down the page: bring it into view
	if body.vertical:
		_reveal_card.call_deferred()


func _reveal_card() -> void:
	if _open and is_inside_tree():
		var top := card.get_global_rect().position.y - scroll.get_global_rect().position.y + float(scroll.scroll_vertical)
		scroll.scroll_vertical = maxi(0, int(top) - 6)


## The survivor the player plays (round 17), or null in the game without one: they always go on a trip they play, and lead it.
func avatar():
	if sim == null or String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## How many OTHERS can go: three on foot, the seats of the vehicle that is chosen; with an avatar they take one of the places.
func party_limit() -> int:
	var seats := int(scav.MAX_PARTY_TOWN)
	if vehicle_id != "":
		seats = int(sim.vehicles.kind_of(vehicle_id).get("seats", scav.MAX_PARTY_TOWN))
	return seats - (1 if avatar() != null else 0)


## Puts `p` in the party, or takes them out (the first of the party leads). Three is the most on foot (a vehicle's
## seats in a vehicle: the rules' own words say so), and the party is never empty while someone could go. True if the
## party changed.
func toggle_member(p) -> bool:
	if not chips.has(p.id) or p == avatar():
		return false
	if party.has(p):
		if party.size() <= 1:
			return false
		party.erase(p)
	else:
		if party.size() >= party_limit():
			var going := party.size() + 1 + (1 if avatar() != null else 0)
			if vehicle_id != "":
				_say(String(sim.vehicles.why_not_use(vehicle_id, going, "")), "warn")
			elif avatar() != null:
				_say("Two is the most: you go too.", "warn")
			else:
				_say("Three is the most.", "warn")
			return false
		party.append(p)
	error_label.visible = false
	hud.ui_sound("ui_click")
	refresh(true)
	return true


## Chooses how the party goes: a parked vehicle's id, or "" for on foot. False if that vehicle is not parked (the
## page says so). The party keeps its people: one that is too big for the seats cannot go, and the buttons say why.
func choose_vehicle(id: String) -> bool:
	if id != "" and not _is_parked(id):
		_say("That vehicle is not at the gate.", "warn")
		return false
	if id == vehicle_id:
		return true
	vehicle_id = id
	error_label.visible = false
	hud.ui_sound("ui_click")
	refresh(true)
	return true


func _is_parked(id: String) -> bool:
	for v in sim.vehicles.parked():
		if String(v.id) == id:
			return true
	return false


## "the pickup" ("" on foot): the way the party goes, in words.
func _ride_name(id: String) -> String:
	return String(sim.vehicles.name_of(id)).to_lower() if id != "" else ""


## "7" or "7.5": a number of fuel.
static func _num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


# ----------------------------------------------------------------- the reasons --

## Why the party cannot do `action` at the place that is chosen ("" when it can): the words of the rules
## (`why_not`, `why_not_action`) where they have them, and the page's own for Claim, Garrison and Recall.
func reason_for(action: String) -> String:
	if site_id == "" or not sites.has(site_id):
		return "Pick a place on the map first."
	var s: Dictionary = sites[site_id]
	match action:
		"loot", "scout", "clear":
			var why: String = scav.why_not()
			if why != "":
				return why
			if party.is_empty():
				return "Pick who goes."
			if vehicle_id == "" and party.size() > int(scav.MAX_PARTY_TOWN):
				return "Three is the most on foot: leave someone at home."
			var place_why: String = scav.why_not_action(party, site_id, action, vehicle_id)
			if place_why == "Picked over." and String(s.get("note", "")) != "":
				return String(s.note)
			return place_why
		"play":
			if not hud.on_raid.is_valid():
				return "Not in this game."
			if String(sim.player_id) != "":
				return _why_not_played(s)
			return reason_for(_played_action(s))
		"claim":
			if String(s.state) == "claimed":
				return "It is already your outpost."
			if String(s.state) != "cleared":
				return "Clear it first: the dead have to be gone."
			var cost := int(s.get("outpost", {}).get("cost", 0))
			if float(sim.stock.scrap) < float(cost):
				return "It takes %d scrap and the stores have %d." % [cost, int(float(sim.stock.scrap))]
			return ""
		"garrison":
			if String(s.state) != "claimed":
				return "Only your own outpost can be held."
			if bool(s.get("needs_vehicle", false)):
				return "Too far to walk to and hold."
			if party.is_empty():
				return "Pick who stays."
			if String(sim.phase) != "day":
				return "Nobody goes out after dark."
			for p in party:
				if not scav.can_go(p):
					return "%s cannot go out now." % p.first
			return ""
		"recall":
			if (s.get("garrison", []) as Array).is_empty():
				return "Nobody is stationed there."
			return town.why_not_recall(site_id)
	return "That cannot be done."


## Why the player cannot take control of a trip to the chosen place now (round 17, "" when they can): the people picked go with
## them (the survivor you play always goes and leads, so a trip with nobody picked is a lone one), judged as the rules of a
## played trip judge it (`scavenge.why_not_played`); the last of the picks stay behind when the seats or the three on foot
## are full (`place_flow.gd`).
func _why_not_played(s: Dictionary) -> String:
	var who: Array = party.duplicate()
	var me = sim.avatar.player()
	if me != null and not who.has(me):
		who.push_front(me)
	var most: int = PlaceFlow.seats(sim, vehicle_id)
	if who.size() > most:
		who = who.slice(0, maxi(most, 1))
	var why: String = scav.why_not_played(who, site_id, _played_action(s), vehicle_id)
	if why == "Picked over." and String(s.get("note", "")) != "":
		return String(s.note)
	return why


## The chance that this party clears this place, as the rules throw it (scavenge.gd's `_decide_town`: 0.35 plus
## 0.08 for each point of Shooting, less 0.12 for each point of danger and nest, kept between 0.1 and 0.95).
func clear_chance(people: Array, id: String) -> float:
	var shooting := 0.0
	for p in people:
		shooting += float(p.skills.get("Shooting", 0))
	var cleared: bool = town.state_of(id) == "cleared"
	var danger := 0 if cleared else int(town.place(id).get("danger", 0))
	var nest := 0 if cleared else int(town.nest_strength(id))
	return clampf(0.35 + 0.08 * shooting - 0.12 * float(danger + nest), 0.1, 0.95)


## "likely", "a risk" or "unlikely".
static func chance_words(chance: float) -> String:
	if chance >= LIKELY_AT:
		return "likely"
	if chance >= RISK_AT:
		return "a risk"
	return "unlikely"


# ----------------------------------------------------------------------- acting --

## Does `action` with the party at the chosen place: "loot" (Go), "scout", "clear", "claim", "garrison" or "recall".
## A trip sends the party through the gate and closes the page; the others are done at once. False, and the page says
## why, if it cannot be done.
func act(action: String) -> bool:
	error_label.visible = false
	var why := reason_for(action)
	if why != "":
		_say(why, "warn")
		hud.ui_sound("ui_error")
		return false
	var s: Dictionary = sites[site_id]
	var where := String(s.name)
	match action:
		"loot", "scout", "clear":
			var going: Array = party.duplicate()
			var ride := vehicle_id
			var sent: bool = scav.send(going, site_id, action, ride)
			if not sent:
				var again: String = scav.why_not()
				_say(again if again != "" else "They could not go out just now.", "warn")
				hud.ui_sound("ui_error")
				return false
			var text := "%s set off %s%s." % [_names(going), _errand(action, where), " in the %s" % _ride_name(ride) if ride != "" else ""]
			var out_party: Dictionary = _party_of(going[0])
			if not out_party.is_empty():
				_departures[int(out_party.n)] = float(sim.clock_min)
			var due := _due_text(out_party)
			if due != "":
				text += " " + due.substr(0, 1).to_upper() + due.substr(1) + "."
			hud.ui_sound("ui_confirm")
			close()
			hud.toast(text)
			return true
		"play":
			return _play(s, where)
		"claim":
			if not town.claim(site_id):
				_say("It cannot be claimed.", "warn")
				hud.ui_sound("ui_error")
				return false
			hud.ui_sound("ui_confirm")
			refresh(true)
			_say("%s is yours now." % where, "ok")
			return true
		"garrison":
			var staying: Array = party.duplicate()
			if not town.garrison_send(site_id, staying):
				_say("They could not go out just now.", "warn")
				hud.ui_sound("ui_error")
				return false
			hud.ui_sound("ui_confirm")
			refresh(true)
			_say("%s %s at %s until you call them home." % [_names(staying), "stays" if staying.size() == 1 else "stay", where], "ok")
			return true
		"recall":
			var crew: Array = s.get("garrison", []).duplicate()
			var who: Array = []
			for pid in crew:
				for p in sim.people:
					if String(p.id) == String(pid):
						who.append(p)
			town.recall(site_id)
			hud.ui_sound("ui_confirm")
			refresh(true)
			_say("%s is on the way home from %s." % [_names(who), where] if not who.is_empty() else "Nobody was there.", "ok")
			return true
	return false


## The action a played trip is sent as: looting, or clearing when there is nothing here to take but the dead.
func _played_action(s: Dictionary) -> String:
	return "loot" if (s.get("actions", []) as Array).has("loot") else "clear"


## Takes control of the party (round 17): the page closes and main.gd's `open_raid` asks the people over the radio, begins the
## trip (the colony's party is made there: `scavenge.begin_played`) and drives the road, the place, the road home and the report
## (scripts/raid/place_flow.gd, raid_scene.gd). The scene finishes the party itself when the place is over, so the callback
## has nothing to send: it is called with the trip's result when the report is dismissed. `open_raid` says why it could not
## begin when it could not (a toast).
func _play(s: Dictionary, _where: String) -> bool:
	var going: Array = party.duplicate()
	var ride := vehicle_id
	var place: Dictionary = town.place(site_id).duplicate(true)
	place["id"] = site_id
	# a place that has been cleared has few of the dead left (the dice zero its danger and nest too)
	if town.state_of(site_id) == "cleared" or town.state_of(site_id) == "claimed":
		place["cleared"] = true
	var id := site_id
	var penalty: float = scav.raid_penalty(id)
	var hud_ref = hud
	hud.ui_sound("ui_confirm")
	close()
	var done := func(_result: Dictionary) -> void:
		pass
	var scene = hud_ref.on_raid.call(going, place, ride, penalty, done)
	return scene != null


## "to look the place over", "to search the pharmacy": the errand in words.
static func _errand(action: String, where: String) -> String:
	match action:
		"scout":
			return "to scout the way to %s" % where
		"clear":
			return "to clear %s" % where
	return "for %s" % where


func _party_of(p) -> Dictionary:
	for party_out in scav.parties:
		if party_out.members.has(p.id):
			return party_out
	return {}


func _say(text: String, level: String = "warn") -> void:
	error_label.text = text
	error_label.add_theme_color_override("font_color", hud.SLIP_MARK.danger if level == "warn" else hud.SLIP_MARK.info)
	error_label.visible = text != ""


# --------------------------------------------------------------------- refresh --

## What the page shows, in one line: it is redrawn only when it changes.
func _signature() -> String:
	var sig := "%s|%d|%d|%s|" % [site_id, int(float(sim.stock.scrap)), floori(sim.clock_min / 5.0), String(sim.phase)]
	for id in town.state:
		var st: Dictionary = town.state[id]
		sig += "%s:%d%d%d%d:%s;" % [id, int(bool(st.known)), int(bool(st.cleared)), int(bool(st.claimed)), int(bool(st.rescued)), ",".join(town.garrison_of(id))]
	for party_out in scav.parties:
		sig += "p%d:%s:%d:%s;" % [int(party_out.n), String(party_out.state), int(float(party_out.return_at)), ",".join(party_out.members)]
	for p in scav.free_survivors():
		sig += "f%s;" % p.id
	for p in party:
		sig += "m%s;" % p.id
	sig += "|%s|%d|" % [vehicle_id, int(float(sim.vehicles.fuel))]
	for v in sim.vehicles.fleet:
		sig += "v%s:%s:%d;" % [v.id, v.state, int(float(v.hp))]
	return sig


## Brings the page in line with the game: the pins, the card, the party and the buttons, the foot. It is safe at any
## time: a place that is revealed, a person who is free to go or no longer is, a party that comes back.
func refresh(force: bool = false) -> void:
	if not _open:
		return
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	sites = {}
	for s in scav.available_sites():
		sites[String(s.id)] = s
	if site_id != "" and not sites.has(site_id):
		site_id = ""
	_sync_party()
	_sync_vehicle()
	_refresh_map()
	_refresh_card()
	_refresh_party()
	_refresh_ride()
	_refresh_buttons()
	_refresh_out()


## The people who are still free to go stay in the party; if nobody of it is left, the first who is free leads.
func _sync_party() -> void:
	var free_people: Array = scav.free_survivors()
	var keep: Array = []
	for p in party:
		if free_people.has(p):
			keep.append(p)
	if keep.is_empty() and not free_people.is_empty():
		keep.append(free_people[0])
	party = keep


## The vehicle that was chosen is still parked, or the party goes on foot.
func _sync_vehicle() -> void:
	if vehicle_id != "" and not _is_parked(vehicle_id):
		vehicle_id = ""


func _refresh_map() -> void:
	var shown: Array = []
	var unknown: Array = []
	var by_id := {}
	for e in town.all_places():
		var id := String(e.id)
		by_id[id] = e
		if String(e.state) == "unknown":
			unknown.append({"id": id, "pos": _unknown_spot(e)})
		else:
			e["survivor"] = bool(e.get("survivor", false)) and not bool(e.get("rescued", false))
			shown.append(e)
	var roads: Array = []
	var streets: Array = []
	for r in town.roads:
		if not (r is Array) or r.size() < 2:
			continue
		var a := String(r[0])
		var b := String(r[1])
		var pa: Vector2 = town.home if a == "home" else Vector2(by_id[a].pos) if by_id.has(a) else Vector2.INF
		var pb: Vector2 = town.home if b == "home" else Vector2(by_id[b].pos) if by_id.has(b) else Vector2.INF
		if pa == Vector2.INF or pb == Vector2.INF:
			continue
		streets.append([pa, pb])
		var ka: bool = a == "home" or String(by_id[a].state) != "unknown"
		var kb: bool = b == "home" or String(by_id[b].state) != "unknown"
		if ka and kb:
			roads.append({"a": pa, "b": pb, "stub": false})
		elif ka:
			roads.append({"a": pa, "b": pa.lerp(pb, 0.42), "stub": true})
		elif kb:
			roads.append({"a": pb, "b": pb.lerp(pa, 0.42), "stub": true})
	map.set_data({
		"board": Vector2(float(town.board.w), float(town.board.h)), "home": town.home, "places": shown, "roads": roads,
		"unknown": unknown, "streets": streets, "parties": _party_markers(), "chosen": site_id,
	})


## Where the "?" of a place that is not known goes: near it, not on it (a few tiles off, the same each time).
func _unknown_spot(e: Dictionary) -> Vector2:
	var h: int = String(e.id).hash()
	var dx := float((h % 9) - 4) / 4.0 * Map.UNKNOWN_SHIFT
	var dy := float(((h / 9) % 9) - 4) / 4.0 * Map.UNKNOWN_SHIFT
	return Vector2(e.pos) + Vector2(dx, dy)


## The parties out as the map draws them: the route from the school, how far along it they are, and which way.
func _party_markers() -> Array:
	var out: Array = []
	for party_out in scav.parties:
		var id := String(party_out.site)
		if not sites.has(id) and town.place(id).is_empty():
			continue
		var action := String(party_out.get("action", "loot"))
		var ride := String(party_out.get("vehicle", ""))
		var trip_h: float = maxf(scav.action_hours(id, action, ride), 0.01)
		var one_way: float = (sim.vehicles.drive_hours(id, ride) / 2.0) if ride != "" else town.hours_to(id)
		var search := maxf(0.0, trip_h - 2.0 * one_way)
		# how much of the trip is gone: from when they set off (the rules do not keep the hour: the page does, from
		# the moment it sees them go; a party seen first later is taken to have set off one trip's time before it is due,
		# which is a little early if the road held them up) to when they are due
		var n := int(party_out.n)
		var depart: float
		if party_out.has("depart"):
			depart = float(party_out.depart)
		elif _departures.has(n):
			depart = float(_departures[n])
		elif String(party_out.state) == "out" or String(party_out.state) == "driving_out":
			depart = float(sim.clock_min)    # still walking to the gate (or driving out): they have only just been sent
		else:
			depart = float(party_out.return_at) - trip_h * 60.0
		_departures[n] = depart
		var span := maxf(float(party_out.return_at) - depart, 1.0)
		var share := clampf((float(sim.clock_min) - depart) / span, 0.0, 1.0)
		var there := one_way / trip_h
		var searched := (one_way + search) / trip_h
		var at := 0.0
		var mode := "out"
		if String(party_out.state) == "out" or String(party_out.state) == "driving_out":
			at = 0.0    # (the car's drive out is not on the map: the trip's hours start when it has left)
		elif share < there:
			at = share / maxf(there, 0.0001)
		elif share < searched:
			at = 1.0
			mode = "search"
		else:
			at = 1.0 - (share - searched) / maxf(1.0 - searched, 0.0001)
			mode = "back"
		out.append({"n": int(party_out.n), "count": party_out.members.size(), "path": route_to(id), "at": clampf(at, 0.0, 1.0), "mode": mode, "vehicle": String(sim.vehicles.kind_of(ride).get("name", "")) if ride != "" else ""})
	return out


## The way a party takes from the school to a place: the roads of the board (the shortest by length), as points in
## board tiles; a straight line if the place has no road.
func route_to(id: String) -> Array:
	if _routes.has(id):
		return _routes[id]
	var pos := {"home": town.home}
	for p in town.places:
		pos[String(p.id)] = Vector2(p.pos)
	var edges := {}
	for r in town.roads:
		if r is Array and r.size() >= 2 and pos.has(String(r[0])) and pos.has(String(r[1])):
			var a := String(r[0])
			var b := String(r[1])
			var len := Vector2(pos[a]).distance_to(pos[b])
			edges[a] = edges.get(a, []) + [[b, len]]
			edges[b] = edges.get(b, []) + [[a, len]]
	var dist := {"home": 0.0}
	var prev := {}
	var open: Array = ["home"]
	while not open.is_empty():
		open.sort_custom(func(x, y): return float(dist[x]) < float(dist[y]))
		var cur: String = open.pop_front()
		for e in edges.get(cur, []):
			var nd: float = float(dist[cur]) + float(e[1])
			if not dist.has(e[0]) or nd < float(dist[e[0]]) - 1.0e-9:
				dist[e[0]] = nd
				prev[e[0]] = cur
				if not open.has(e[0]):
					open.append(e[0])
	var path: Array = []
	if pos.has(id):
		if prev.has(id):
			var at := id
			while at != "home":
				path.push_front(Vector2(pos[at]))
				at = String(prev[at])
			path.push_front(town.home)
		else:
			path = [town.home, Vector2(pos[id])]
	_routes[id] = path
	return path


# ------------------------------------------------------------------------ the card --

func _fact_set(key: String, text: String, shown: bool = true) -> void:
	var f: Dictionary = facts[key]
	f.cap.visible = shown
	f.value.visible = shown
	f.label.text = text


func _refresh_card() -> void:
	var has := site_id != "" and sites.has(site_id)
	empty_label.visible = not has
	place_view.visible = has
	if not has:
		return
	var s: Dictionary = sites[site_id]
	var state := String(s.state)
	name_label.text = String(s.name)
	var picture := _site_texture(String(s.get("image", "")))
	thumb.texture = picture
	thumb.visible = picture != null
	for c in tag_flow.get_children():
		tag_flow.remove_child(c)
		c.queue_free()
	if state == "cleared":
		tag_flow.add_child(_tag("Cleared", Map.GREEN))
	elif state == "claimed":
		tag_flow.add_child(_tag("Your outpost", Dialog.GOLD_INK))
	var strength := int(s.get("nest", {}).get("strength", 0)) if s.get("nest", {}) is Dictionary else 0
	if strength > 0 and state != "cleared" and state != "claimed":
		tag_flow.add_child(_tag("Nest %d" % strength, Map.RED))
	if bool(s.get("needs_vehicle", false)):
		tag_flow.add_child(_tag("By vehicle only", Map.BLUE))
	tag_flow.visible = tag_flow.get_child_count() > 0
	blurb_label.text = String(s.get("blurb", ""))

	# danger
	var danger := clampi(int(s.get("danger", 1)), 0, 3)
	var gone := state == "cleared" or state == "claimed"
	var shown_danger := 0 if gone else danger
	for i in 3:
		var pip: Panel = pip_row.get_child(i)
		var st := StyleBoxFlat.new()
		st.bg_color = (hud.SLIP_MARK.danger if shown_danger >= 3 else hud.SLIP_MARK.warn) if i < shown_danger else Color(hud.PAPER_INK, 0.18)
		st.set_corner_radius_all(5)
		st.anti_aliasing = true
		pip.add_theme_stylebox_override("panel", st)
	_fact_set("danger", "None left: the dead are gone" if gone else String(DANGER_WORDS[danger]))
	pip_row.tooltip_text = "Danger %d of 3" % shown_danger
	pip_row.mouse_filter = Control.MOUSE_FILTER_PASS

	# the trip
	_fact_set("trip", _trip_text(s))
	# a vehicle that stands in the place: looting (or clearing) it may get it running
	var here_kind := String(s.get("vehicle_here", ""))
	if here_kind != "" and not sim.vehicles.kind(here_kind).is_empty():
		var kind_name := String(sim.vehicles.kind(here_kind).name).to_lower()
		_fact_set("vehicle", "%s %s stands here: loot it to try to get it running." % ["An" if kind_name.substr(0, 1) in ["a", "e", "i", "o", "u"] else "A", kind_name])
	else:
		_fact_set("vehicle", "", false)
	# what it is likely to give
	_fact_set("loot", String(s.get("loot_hint", "")))
	for c in chips_box.get_children():
		chips_box.remove_child(c)
		c.queue_free()
	var loot = s.get("loot", {})
	var extra = s.get("extra", {})
	if loot is Dictionary:
		for k in LOOT_ORDER:
			if loot.has(k):
				chips_box.add_child(_chip(k, _range_text(loot[k]), hud.PAPER_INK))
		if extra is Dictionary:
			for k in LOOT_ORDER:
				if extra.has(k):
					chips_box.add_child(_chip(k, "sometimes", hud.PAPER_INK3))
	chips_box.visible = chips_box.get_child_count() > 0
	# what has been done to it
	var note := String(s.get("note", ""))
	_fact_set("note", note, note != "" and state != "claimed")
	# the nest, the one hiding, the outpost, the garrison
	var original_nest := int(town.nest_strength(site_id))
	if original_nest > 0 and not gone:
		_fact_set("nest", "Strength %d. %s" % [original_nest, _nest_lean(site_id)])
	elif original_nest > 0:
		_fact_set("nest", "Gone: the nights are quieter for it.")
	else:
		_fact_set("nest", "", false)
	var hiding := bool(s.get("survivor", false))
	_fact_set("hiding", "Someone is hiding here: a rescue may come home." if hiding else "", hiding)
	var outpost: Dictionary = s.get("outpost", {}) if s.get("outpost", {}) is Dictionary else {}
	if outpost.is_empty():
		_fact_set("outpost", "", false)
	elif state == "claimed":
		_fact_set("outpost", "Yours: %s a day. Empty, it can be overrun at night." % _yield_text(outpost.get("yield", {})))
	elif state == "cleared":
		_fact_set("outpost", "Can be claimed: %s a day, for %d scrap." % [_yield_text(outpost.get("yield", {})), int(outpost.get("cost", 0))])
	else:
		_fact_set("outpost", "Once cleared: %s a day, for %d scrap." % [_yield_text(outpost.get("yield", {})), int(outpost.get("cost", 0))])
	var holders := _garrison_names(s.get("garrison", []))
	_fact_set("held", holders if holders != "" else "Nobody. It is unguarded.", state == "claimed")
	# the chance of clearing it
	var can_clear: bool = (s.get("actions", []) as Array).has("clear")
	var crowd: Array = party.duplicate()
	if avatar() != null:
		crowd.push_front(avatar())    # (the player goes, and shoots, too)
	if can_clear and not crowd.is_empty():
		var chance := clear_chance(crowd, site_id)
		_fact_set("clear", "%s with %s." % [chance_words(chance).capitalize(), _names(crowd)])
	else:
		_fact_set("clear", "", false)


func _nest_lean(id: String) -> String:
	var spawns: Array = sim.spawns
	if spawns.is_empty():
		return "The nights lean this way."
	var idx: int = town.heading_of(town.place(id))
	return "The nights lean to the %s." % Waves.direction_name(spawns[clampi(idx, 0, spawns.size() - 1)])


func _trip_text(s: Dictionary) -> String:
	var by_vehicle := vehicle_id != ""
	if bool(s.get("needs_vehicle", false)) and not by_vehicle:
		return "Too far to walk: it takes a vehicle."
	var hours := float(s.get("trip_hours", 0.0))
	if by_vehicle:
		hours = scav.action_hours(site_id, "loot", vehicle_id)
	var words := Map.hours_text(hours)
	var text := "%s there and back" % (words.substr(0, 1).to_upper() + words.substr(1))
	if by_vehicle:
		text += " by the %s (%s fuel)" % [_ride_name(vehicle_id), _num(sim.vehicles.fuel_for(site_id, vehicle_id))]
	text += "."
	var start := clampf(float(sim.hour), FIRST_LIGHT_H, LEAVE_BY_H) if scav.can_send() else 7.0
	var back := start + hours
	if back >= float(sim.seasons.dusk_hour()):
		text += " Back tomorrow: a night out, and no one on the wall."
	else:
		text += " Back about %s." % _clock(back)
	return text


## "14:30": an hour of the day, to the nearest quarter of an hour.
static func _clock(hour: float) -> String:
	var q := roundi(fposmod(hour, 24.0) * 4.0)
	return "%02d:%02d" % [(q / 4) % 24, (q % 4) * 15]


func _chip(stock: String, text: String, color: Color) -> Control:
	var row: HBoxContainer = hud._hbox(4)
	var ic: TextureRect = hud._icon(stock, 14, hud.PAPER_INK2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(hud._label(text, Fonts.cond(600), 14, color))
	row.tooltip_text = LOOT_NAME.get(stock, stock)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


static func _range_text(r) -> String:
	if r is Array and r.size() >= 2:
		var lo := int(r[0])
		var hi := int(r[1])
		return "%d" % lo if lo == hi else "%d–%d" % [lo, hi]
	return str(r)


## "4 food and 2 water", "0.8 medicine".
static func _yield_text(y) -> String:
	var parts: Array = []
	if y is Dictionary:
		for k in Dialog.STOCK_ORDER:
			if y.has(k):
				var n := float(y[k])
				var count := str(roundi(n)) if absf(n - roundf(n)) < 0.05 else "%.1f" % n
				parts.append("%s %s" % [count, String(Dialog.STOCK_NAME.get(k, k)).to_lower()])
	if parts.is_empty():
		return "nothing"
	return _join(parts)


static func _join(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


## "Walt", "Walt and Hector", "Walt, Hector and Dez" (Person objects).
static func _names(people: Array) -> String:
	var names: Array = []
	for p in people:
		names.append(String(p.first))
	return _join(names)


func _garrison_names(ids: Array) -> String:
	var names: Array = []
	for pid in ids:
		for p in sim.people:
			if String(p.id) == String(pid):
				names.append(String(p.first))
	return _join(names)


## The place's picture if the file is there (imported, or a plain PNG in a checkout that has not been imported yet).
func _site_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# -------------------------------------------------------------- party and buttons --

func _refresh_party() -> void:
	var free_people: Array = scav.free_survivors()
	var me = avatar()
	var free_sig := "me:%s;" % (String(me.id) if me != null else "")
	for p in free_people:
		free_sig += "%s;" % p.id
	# the people on offer are made again only when they change
	if free_sig != _free_sig:
		_free_sig = free_sig
		for id in chips:
			chips[id].chip.queue_free()
		chips.clear()
		me_chip = null
		for c in chip_flow.get_children():
			chip_flow.remove_child(c)
			c.queue_free()
		if me != null:
			# the player first: they lead, and go whoever else does
			me_chip = _person_chip(me, true)
			chip_flow.add_child(me_chip)
		for p in free_people:
			var chip := _person_chip(p)
			chip_flow.add_child(chip)
	for id in chips:
		var e: Dictionary = chips[id]
		var in_party: bool = party.has(e.person)
		var leads: bool = me == null and not party.is_empty() and party[0] == e.person
		_style_chip(e.chip, in_party, leads)
		e.lead.visible = leads
		var who: String = e.person.first
		e.chip.tooltip_text = ("%s leads the party. Click to leave them at home." % who if leads else "%s is going. Click to leave them at home." % who) if in_party else "Click to bring %s along." % who
	_note_label.text = _note
	_note_label.visible = _note != "" and not free_people.is_empty()
	if free_people.is_empty():
		_tip_label.text = "Nobody is free to go."
	else:
		var most := "Three is the most." if vehicle_id == "" else "The %s seats %d." % [_ride_name(vehicle_id), party_limit()]
		var leads_line := "%s leads. " % party[0].first if not party.is_empty() else ""
		if me != null:
			# (the player leads: two others on foot, the seats less one in a vehicle)
			most = "Two is the most." if vehicle_id == "" else "The %s seats %d: you and %d more." % [_ride_name(vehicle_id), party_limit() + 1, party_limit()]
			leads_line = "You lead. "
		_tip_label.text = "%sClick someone to bring them along. %s" % [leads_line, most]
	var effect := ""
	# (these are the dice's rules, for a trip that goes without the player: with an avatar Go's tooltip says it sends them without you)
	if party.size() == 1 and me == null:
		effect = "A lone scavenger brings back less."
	for p in party:
		if me == null and int(p.skills.get("Leading", 0)) >= int(scav.LEADER_SKILL):
			effect += ("" if effect == "" else " ") + "%s leads well: the party finds a little more." % p.first
			break
	_effect_label.text = effect
	_effect_label.visible = effect != ""
	# what the trip leaves empty at home (the radio desk, the lookout post...) and how many stay to hold the yard
	var leaves := CrewLoad.trip_line(sim, party) if not free_people.is_empty() else ""
	leave_label.text = leaves
	leave_label.visible = leaves != ""
	hint_label.text = "Arrows and Tab go between the pins, Enter picks one. G or Esc closes."


## A person's chip: a portrait, a name and the skills that matter for a trip.
func _person_chip(p, is_me: bool = false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	b.add_theme_stylebox_override("focus", Kit.focus_box(Dialog.GOLD_EDGE, 5))
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	var row: HBoxContainer = hud._hbox(8)
	var pic := TextureRect.new()
	pic.texture = hud.portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(34, 34)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var text: VBoxContainer = hud._vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = hud._hbox(3)
	# the one who leads has a star before their name
	var lead: TextureRect = hud._icon("star", 13, Dialog.GOLD_INK)
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead.visible = is_me
	top.add_child(lead)
	top.add_child(hud._label(String(p.first), Fonts.cond(700), 16, hud.PAPER_INK))
	text.add_child(top)
	text.add_child(hud._label("Shooting %d" % int(p.skills.get("Shooting", 0)), Fonts.sans(400), 12, hud.PAPER_INK2))
	if is_me:
		text.add_child(hud._label("You lead", Fonts.sans(600), 12, hud.PAPER_INK))
	else:
		text.add_child(hud._label("Leading %d" % int(p.skills.get("Leading", 0)), Fonts.sans(400), 12, hud.PAPER_INK2))
	row.add_child(text)
	pad.add_child(row)
	b.add_child(pad)
	b.set_meta("person", p.id)
	if is_me:
		# the player is not a choice: they go, and lead (the click does nothing; the tooltip says why)
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		b.tooltip_text = "You lead, and you always go. Take control to play the trip; Go sends the others without you."
		_style_chip(b, true, true)
		return b
	b.pressed.connect(toggle_member.bind(p))
	chips[p.id] = {"chip": b, "person": p, "lead": lead}
	_style_chip(b, false, false)
	return b


## The look of a chip: a light card with a pencil edge; gold, with a heavy edge, while the person is in the party.
func _style_chip(b: Button, in_party: bool, leads: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Dialog.CARD_CHOSEN if in_party else Dialog.CARD
		s.border_color = Dialog.GOLD_EDGE if in_party else Color(hud.PAPER_INK, 0.3)
		if state == "hover" and not in_party:
			s.bg_color = Dialog.CARD_CHOSEN.lerp(Dialog.CARD, 0.5)
			s.border_color = Dialog.GOLD_EDGE
		elif state == "pressed":
			s.bg_color = Dialog.CARD_CHOSEN.darkened(0.06)
		s.set_border_width_all(3 if leads else (2 if in_party else 1))
		s.set_corner_radius_all(5)
		s.anti_aliasing = true
		b.add_theme_stylebox_override(state, s)


## The ride: "On foot" and a chip for each vehicle that is parked, with what the trip to the chosen place would take of
## each (fuel, hours). Only there while a vehicle is parked. The chips are made again only when what they say changes.
func _refresh_ride() -> void:
	var parked: Array = sim.vehicles.parked()
	ride_box.visible = not parked.is_empty()
	if parked.is_empty():
		for c in ride_flow.get_children():
			ride_flow.remove_child(c)
			c.queue_free()
		ride_chips.clear()
		_ride_sig = ""
		return
	var entries := ride_entries(parked)
	var sig := ""
	for e in entries:
		sig += "%s|%s|%s|%s|%s;" % [e.id, e.name, e.l2, e.l3, str(e.warn)]
	if sig != _ride_sig:
		_ride_sig = sig
		for c in ride_flow.get_children():
			ride_flow.remove_child(c)
			c.queue_free()
		ride_chips.clear()
		for e in entries:
			var chip := _ride_chip(e)
			ride_flow.add_child(chip)
	for e in entries:
		var entry: Dictionary = ride_chips.get(e.id, {})
		if entry.is_empty():
			continue
		var chosen: bool = String(e.id) == vehicle_id
		_style_chip(entry.chip, chosen, false)
		var chip_tip := String(e.tip)
		entry.chip.tooltip_text = ("%s\nGoing this way. Click \"On foot\" to walk." % chip_tip if String(e.id) != "" else "%s\nGoing on foot." % chip_tip) if chosen else "%s\nClick to go this way." % chip_tip
	ride_tip.text = "The tank has %s fuel." % _num(sim.vehicles.fuel)


## What each way to go says for the chosen place: [{"id" ("" on foot), "name", "l2", "l3", "warn", "tip", "glyph"}]. The
## fuel and the hours are those of the trip to the place that is chosen; with none chosen the vehicle's burn is told.
func ride_entries(parked: Array) -> Array:
	var s: Dictionary = sites.get(site_id, {})
	var has := site_id != "" and not s.is_empty()
	var far: bool = has and bool(s.get("needs_vehicle", false))
	var out: Array = []
	var foot := {"id": "", "name": "On foot", "l2": "Up to %d people" % int(scav.MAX_PARTY_TOWN), "l3": "", "warn": far, "glyph": "foot",
		"tip": "On foot: up to %d people, the road at a walking pace, no fuel." % int(scav.MAX_PARTY_TOWN)}
	if far:
		foot.l3 = "Too far to walk"
	elif has:
		foot.l3 = Map.hours_text(float(s.get("trip_hours", 0.0)))
	out.append(foot)
	for v in parked:
		var k: Dictionary = sim.vehicles.kind_of(String(v.id))
		var l2 := "%d seats" % int(k.seats)
		var l3 := ""
		var warn := false
		if has:
			var need: float = sim.vehicles.fuel_for(site_id, String(v.id))
			l2 += ", fuel %s" % _num(need)
			l3 = Map.hours_text(scav.action_hours(site_id, "loot", String(v.id)))
			warn = float(sim.vehicles.fuel) + 1.0e-9 < need
		else:
			l3 = "burns %s an hour" % _num(float(k.burn))
		if party.size() + (1 if avatar() != null else 0) > int(k.seats):
			warn = true
		var worn := int(roundf(100.0 * float(v.hp) / maxf(float(k.hp), 1.0)))
		out.append({"id": String(v.id), "name": String(k.name), "l2": l2, "l3": l3, "warn": warn, "glyph": "bus" if String(v.kind).contains("bus") else "car",
			"tip": "%s: %d seats, %s times a walker's pace, burns %s fuel an hour, brings back %s times the loot. Condition %d%%." % [String(k.name), int(k.seats), _num(float(k.speed)), _num(float(k.burn)), _num(float(k.cargo)), worn]})
	return out


## A vehicle's chip, or the "On foot" one: a picture, its name, its seats and fuel, the hours.
func _ride_chip(e: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(RIDE_W, RIDE_H)
	b.add_theme_stylebox_override("focus", Kit.focus_box(Dialog.GOLD_EDGE, 5))
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	var row: HBoxContainer = hud._hbox(7)
	var icon := RideIcon.new()
	icon.glyph = String(e.glyph)
	icon.ink = hud.PAPER_INK
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text: VBoxContainer = hud._vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = hud._label(String(e.name), Fonts.cond(700), 16, hud.PAPER_INK)
	text.add_child(name_label)
	var warn_ink: Color = WHY_INK if bool(e.warn) else hud.PAPER_INK2
	var l2: Label = hud._label(String(e.l2), Fonts.sans(400 if not bool(e.warn) else 600), 12, warn_ink)
	text.add_child(l2)
	var l3: Label = hud._label(String(e.l3), Fonts.sans(400), 12, WHY_INK if String(e.l3) == "Too far to walk" else hud.PAPER_INK2)
	l3.visible = String(e.l3) != ""
	text.add_child(l3)
	row.add_child(text)
	pad.add_child(row)
	b.add_child(pad)
	var id := String(e.id)
	b.pressed.connect(choose_vehicle.bind(id))
	b.set_meta("vehicle", id)
	ride_chips[id] = {"chip": b, "name": name_label, "l2": l2, "l3": l3}
	_style_chip(b, false, false)
	return b


## The avatar's board (round 17): Take control, the trip they play, is the first and the main button; Go (the dice's trip, without them)
## is the plainer one. The game without an avatar has Go first and gold, as ever.
func _apply_avatar_buttons() -> void:
	var on: bool = avatar() != null and hud.on_raid.is_valid()
	if on == _avatar_buttons:
		return
	_avatar_buttons = on
	_set_primary(play_button, on)
	_set_primary(go_button, not on)
	var flow: Node = go_button.get_parent()
	flow.move_child(play_button if on else go_button, 0)


## Gives a button of the page the main choice's look (gold) or the plain one (the HUD's own styles for each).
func _set_primary(b: Button, on: bool) -> void:
	var look: Button = hud._button(b.text, on, true)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, look.get_theme_stylebox(state))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(key, look.get_theme_color(key))
	b.add_theme_stylebox_override("focus", Kit.focus_box(hud.INK if on else hud.ACCENT))
	look.free()


func _refresh_buttons() -> void:
	_apply_avatar_buttons()
	var s: Dictionary = sites.get(site_id, {})
	var state := String(s.get("state", ""))
	var has_outpost: bool = s.get("outpost", {}) is Dictionary and not (s.get("outpost", {}) as Dictionary).is_empty()
	var claimed := state == "claimed"
	var shown := {
		"loot": true, "scout": true, "clear": true, "play": hud.on_raid.is_valid(),
		"claim": site_id == "" or has_outpost,
		"garrison": site_id == "" or claimed,
		"recall": site_id == "" or claimed,
	}
	var why_of := {}
	for action in buttons:
		var b: Button = buttons[action]
		b.visible = bool(shown[action])
		var why := reason_for(action)
		why_of[action] = why
		b.disabled = why != ""
		b.focus_mode = Control.FOCUS_NONE if why != "" else Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if why != "" else Control.CURSOR_POINTING_HAND
		b.tooltip_text = why if why != "" else (AVATAR_GO_TIP if action == "loot" and _avatar_buttons else _action_tip(action, s))
	_say_why(why_of)


## The lines under the buttons: what is off and why, the buttons with the same reason together ("Go, Scout and Clear:
## Nobody goes out after dark.").
func _say_why(why_of: Dictionary) -> void:
	_why_of = {}
	var groups: Array = []
	for action in buttons:
		var why: String = why_of[action]
		if why == "" or not buttons[action].visible:
			continue
		var found := false
		for g in groups:
			if g.why == why:
				g.names.append(String(buttons[action].text))
				g.actions.append(action)
				found = true
		if not found:
			groups.append({"why": why, "names": [String(buttons[action].text)], "actions": [action]})
	for i in why_lines.size():
		var line: Label = why_lines[i]
		if i < groups.size():
			var text := "%s: %s" % [_join(groups[i].names), groups[i].why]
			line.text = text
			line.visible = true
			for action in groups[i].actions:
				_why_of[action] = text
		else:
			line.text = ""
			line.visible = false


## The line under the buttons that says why this action is off ("" when it is not off).
func why_line_for(action: String) -> String:
	return String(_why_of.get(action, ""))


## What a button does, for its tooltip (when it can be pressed).
func _action_tip(action: String, s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var where := String(s.name)
	match action:
		"loot":
			return "Send the party to search %s for loot: %s." % [where, Map.hours_text(scav.action_hours(site_id, "loot", vehicle_id))]
		"scout":
			return "Send the party to look the way over: it shows the places near %s, and brings nothing back: %s." % [where, Map.hours_text(scav.action_hours(site_id, "scout", vehicle_id))]
		"play":
			return "Play the trip yourself: your squad goes in and you give the orders. Search what you can, shoot what you must, and get out."
		"clear":
			var chance := clear_chance(party, site_id)
			return "Turn the dead out of %s (and end its nest, if it has one): %s, %s. A failed attempt hurts." % [where, chance_words(chance), Map.hours_text(scav.action_hours(site_id, "clear", vehicle_id))]
		"claim":
			return "Make %s your outpost: %d scrap now, then %s a day." % [where, int(s.get("outpost", {}).get("cost", 0)), _yield_text(s.get("outpost", {}).get("yield", {}))]
		"garrison":
			return "Leave the party at %s to hold it at night, until you recall them." % where
		"recall":
			return "Call the garrison of %s home to the gate." % where
	return ""


# ------------------------------------------------------------------- the foot --

## The parties that are out and the people who hold outposts, each in a slip.
func _refresh_out() -> void:
	var sig := ""
	for party_out in scav.parties:
		sig += "%d:%d:%s:%s;" % [int(party_out.n), int(float(party_out.return_at)), ",".join(party_out.members), String(party_out.get("vehicle", ""))]
	for id in town.garrison:
		sig += "g%s:%s;" % [id, ",".join(town.garrison_of(id))]
	sig += "%d" % floori(sim.clock_min / 5.0)
	if sig == _out_sig:
		return
	_out_sig = sig
	for c in out_box.get_children():
		out_box.remove_child(c)
		c.queue_free()
	var any := false
	for party_out in scav.parties:
		any = true
		var people: Array = []
		for pid in party_out.members:
			for p in sim.people:
				if String(p.id) == String(pid):
					people.append(p)
		var action := String(party_out.get("action", "loot"))
		var where := String(town.place(String(party_out.site)).get("name", String(party_out.site)))
		var ride := String(party_out.get("vehicle", ""))
		var in_it := " in the %s" % _ride_name(ride) if ride != "" else ""
		out_box.add_child(_slip(people, "%s, %s %s%s: %s." % [_names(people), String(ACTION_WORDS.get(action, action)), where, in_it, _due_text(party_out)]))
	for id in town.garrison:
		var holders: Array = []
		for pid in town.garrison_of(id):
			for p in sim.people:
				if String(p.id) == String(pid):
					holders.append(p)
		if holders.is_empty():
			continue
		any = true
		out_box.add_child(_slip(holders, "%s holding %s until recalled." % [_names(holders), String(town.place(String(id)).get("name", String(id)))]))
	if not any:
		out_box.add_child(_para(13, hud.PAPER_INK2))
		(out_box.get_child(0) as Label).text = "Nobody is out."
	out_caption.text = "OUT NOW"


## One party or garrison, as a small slip: the faces and a line.
func _slip(people: Array, words: String) -> Control:
	var s: StyleBoxFlat = hud._flat(Dialog.CARD, 4, Color(hud.PAPER_INK, 0.3), false)
	s.set_border_width_all(1)
	s.content_margin_left = 6
	s.content_margin_right = 9
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	var slip: PanelContainer = hud._panel(s)
	slip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row: HBoxContainer = hud._hbox(6)
	for p in people:
		var pic := TextureRect.new()
		pic.texture = hud.portrait_of(p)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(24, 24)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
	var l: Label = hud._label(words, Fonts.sans(500), 13, hud.PAPER_INK)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	slip.add_child(row)
	return slip


## When a party out is due, in words: "back about 14:30", "back tomorrow", "back in 2 days". (A party comes in by
## day: one that is due after dusk is in at first light.)
func _due_text(party_out: Dictionary) -> String:
	if party_out.is_empty():
		return ""
	var due_abs := float(party_out.return_at) + 420.0
	var due_day := floori(due_abs / 1440.0)
	var due_h := fposmod(due_abs / 60.0, 24.0)
	var now_day := floori((float(sim.clock_min) + 420.0) / 1440.0)
	var arrives := due_day + (1 if due_h >= float(sim.seasons.dusk_hour()) else 0)
	var days := arrives - now_day
	if days <= 0:
		return "back about %s" % _clock(maxf(due_h, FIRST_LIGHT_H))
	if days == 1:
		return "back tomorrow"
	return "back in %d days" % days


# --------------------------------------------------------------------- closing --

func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_input(false)
	hide()
	closed.emit()
	queue_free()


# -------------------------------------------------------------------- keyboard --

## The keyboard goes to the chosen pin, else the first pin (the nearest place), else the Close button.
func focus_default() -> void:
	if not _open or not is_inside_tree():
		return
	if map.pins.has(site_id):
		map.pins[site_id].grab_focus()
		return
	var first = null
	for id in map.pins:
		var pin = map.pins[id]
		if first == null or float(pin.place.get("hours", 0.0)) < float(first.place.get("hours", 0.0)):
			first = pin
	if first != null:
		first.grab_focus()
	else:
		close_button.grab_focus()


## While the page is up every key belongs to it: Esc or G closes it, Tab, the arrows, Enter and Space go on to the
## controls (and Tab or an arrow with nothing focused puts the keyboard on a pin); every other key is not the
## game's.
func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed:
		return
	var code: Key = ev.keycode
	var plain: bool = not ev.ctrl_pressed and not ev.meta_pressed and not ev.alt_pressed
	if ev.echo and (code == KEY_ESCAPE or code == KEY_G):
		# a key that is held down shuts one thing, not the page and then what is under it
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if code == KEY_ESCAPE:
		close()
	elif code == KEY_G and plain:
		close()
	elif code in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and focus == null:
		focus_default()
	elif code in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- the parts --

## The little picture on a ride's chip: a car or a bus (the map's own glyphs), or the walker of "On foot".
class RideIcon:
	extends Control
	var glyph := "car"
	var ink := Color.BLACK

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var at := size / 2.0
		if glyph == "foot":
			Map.draw_badge(self, "figure", at, 11.0)
		else:
			Map.draw_glyph(self, glyph, at, 12.0, ink, Dialog.CARD)
