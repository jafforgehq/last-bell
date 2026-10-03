## The Map page of the radio panel (round 18, V2.4): the Town Board in the panel's compact, non-modal form. The paper map on top (the
## Town Board's own `town_map.gd`: pins, roads, the "?" of what nobody has seen, the parties on their routes, the river chip), the card of
## the place that is chosen (name and kind, tags, the danger in words, the trip's hours on foot and by the vehicle, what it may give, what
## has been done to it), the PEOPLE as chips (who to ask: a face, a first name and under it "willing" or the refusal in amber), the
## vehicles that are parked, and two ways to go:
##
##   Take control   the avatar and the people ticked go and the player plays the trip (`host.on_raid`, exactly as the Town Board's
##                  Take control does: `penalty = scavenge.raid_penalty(place)`); the words of a refusal are `scavenge.why_not_played`'s,
##                  and who would stay behind (they say no, or the seats are full) is what `PlaceFlow.pick_party` says. And (round 19, avatar
##                  mode) a line under it, hidden when empty: what tonight means for the trip as planned, `scavenge.night_warning`'s own
##                  words as the Town Board's "Tonight" row has them (`NightKit.warning_line`): on a Big Night the hour to leave by.
##   Ask <names> to go   an ERRAND: the people ticked are asked over the radio (`radio.request_errand`) to go without the player:
##                  Loot, Scout or Clear (a three-way switch), with what that costs written under the button ("Without you: about 60% of
##                  the loot, ...": `radio.errand_willingness`), who would refuse and why (amber, on their chip, in the list under the
##                  button), and Insist for a soft refusal (trust -6 each: the radio's `INSIST_COST`).
##
## Claim (the cost, "Clear it first") and Recall are the board's (`town.claim`, `town.recall`); Garrison stays on the full page. At the foot,
## the parties that are out and the errands that wait for their delay, and the "Full page" button (the Town Board, `host.open_scavenge`).
##
## Every word of a refusal is the sim's (`radio.reason_not`, `radio.errand_willingness`, `scavenge.why_not_played`, `town.why_not_recall`...);
## the page only lays them out. A control that is off has the reason as its tooltip. Nothing here takes focus (the panel's buttons never
## do: WASD and E keep working). The page is made once by `setup`, brought up to date by `refresh` (the panel does it ten times a second
## while it is open) and does nothing while the game has no board (`sim.town.on`): a message says so.
##
## What the page asks of the game (`host` is the HUD, which lends the looks and `on_raid`, `open_scavenge`, `ui_sound`, `close_radio`;
## all but the looks are optional, so a test's host can leave them out):
##   sim.town, sim.scavenge, sim.vehicles, sim.radio (`reason_not`, `errand_willingness`, `request_errand`, `errand_wait`, `leader`),
##   sim.avatar, sim.player_id, sim.stock, sim.people, sim.clock_min, sim.hour, sim.phase, sim.seasons.
extends VBoxContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Map := preload("res://scripts/ui/town_map.gd")
const MapData := preload("res://scripts/ui/map_data.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const Waves := preload("res://scripts/sim/waves.gd")

## The map is made this wide at most when the pins need more room than the page has (the sheet then scrolls sideways).
const MAP_MAX_W := 900.0
## ... and not taller than this share of the page's width (at least MAP_MIN_H).
const MAP_ASPECT := 0.6
const MAP_MIN_H := 150.0
## A person's chip, a vehicle's chip, a button's height.
const CHIP_W := 126.0
const CHIP_H := 52.0
const RIDE_W := 138.0
const BUTTON_H := 34.0
## How long the answer to an errand stays under the button (real seconds).
const ANSWER_S := 12.0
## The errands the three-way switch offers, and what each is called and does.
const ERRANDS := ["loot", "scout", "clear"]
const ERRAND_NAME := {"loot": "Loot", "scout": "Scout", "clear": "Clear"}
const ERRAND_TIP := {
	"loot": "Search the place for what it has: food, water, scrap, ammo, medicine or fuel.",
	"scout": "Look the way over: it shows the places near, and brings nothing back.",
	"clear": "Turn the dead out of the place (and end its nest, if it has one). A failed attempt hurts.",
}
## The moment of sending is told in these words.
const FOOT_NOBODY := "Nobody is out."

var host
var sim_getter: Callable

## The place that is chosen ("" until one is), what the errand will do there, and how the party goes ("" on foot, or a parked vehicle's id).
var site_id := ""
var errand_action := "loot"
var vehicle_id := ""
## The people ticked (ids, in the order they were ticked): the party of Take control (with the player) and the people an errand asks.
var ticks: Array = []
## Whether the ticked people who refuse softly are pushed (an errand then goes with them, grudgingly, at the cost of trust).
var insist_on := false
## The places the board offers now (`scavenge.available_sites`), by id.
var sites := {}

var map: Control
var map_scroll: ScrollContainer
var body: VBoxContainer
var foot: VBoxContainer
var message_label: Label
var hint_label: Label
var key_button: Button
var key_panel: PanelContainer
## The card of the place and its parts.
var card: PanelContainer
var empty_label: Label
var place_view: VBoxContainer
var name_label: Label
var kind_label: Label
var tag_flow: HFlowContainer
var pip_row: HBoxContainer
var facts := {}
var loot_chips: HFlowContainer
## The people: person id to {"chip": Button, "pic": TextureRect, "name": Label, "status": Label, "tick": Control, "person": Person}.
var chips := {}
var chip_flow: HFlowContainer
var people_hint: Label
var people_box: VBoxContainer
## The vehicles: id ("" is "On foot") to {"chip": Button, "name": Label, "l2": Label, "l3": Label}.
var ride_chips := {}
var ride_box: VBoxContainer
var ride_flow: HFlowContainer
var ride_tip: Label
## The actions.
var buttons := {}
var segments := {}
var go_note: Label
var stay_note: Label
## What tonight means for the trip as it is planned (round 19, in avatar mode: `scavenge.night_warning`; hidden when it has nothing to say).
var night_note: Label
var terms_note: Label
var summary_label: Label
var refusal_box: VBoxContainer
var answer_label: Label
var feedback_label: Label
var claim_row: HFlowContainer
var out_caption: Label
var out_box: VBoxContainer

var _built := false
var _departures := {}
var _routes := {}
var _map_sig := ""
var _card_sig := ""
var _ride_sig := ""
var _people_sig := ""
var _sites_sig := ""
## What `_layout` made of the sheet ({"w", "h", "scale", "view", "avail"}) and the width of the sheet the frame was last put on the school for.
var _sheet := {}
var _centered_w := -1.0
## The answer to the last errand asked: {"ok", "line", "who", "why", "going", "refused", "delay_s", "at" (msec)} ({} when none).
var _answer := {}
var _feedback := {"text": "", "level": "info"}
## Inside `refresh` the sums that are asked of the game more than once (a person's state, the errand's view, who would go on a played
## trip) are worked out once: `_memo`. Outside it every question is asked afresh.
var _memo := {}
var _memoizing := false


func setup(p_host, p_sim_getter: Callable, _options: Dictionary = {}) -> void:
	host = p_host
	sim_getter = p_sim_getter
	if _built:
		return
	_built = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	resized.connect(_layout)
	refresh()


func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _radio():
	var s = _sim()
	return s.radio if s != null else null


## The survivor the player plays, or null (no avatar).
func _avatar():
	var s = _sim()
	if s == null or String(s.player_id) == "":
		return null
	return s.avatar.player()


func _on() -> bool:
	var s = _sim()
	return s != null and s.get("town") != null and bool(s.town.on)


# ------------------------------------------------------------------- build --

func _build() -> void:
	message_label = _para("There is no map in this game: only a settlement game has a town to go out to.", 13, host.INK2)
	message_label.visible = false
	add_child(message_label)
	# (the page is as tall as its content: the panel's own scroll shows what does not fit, the foot with it)
	body = host._vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	# the map, its key and the line that says what to do with it
	var top: HBoxContainer = host._hbox(8)
	hint_label = _para("Tap a pin to choose a place.", 12, host.INK3)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(hint_label)
	key_button = RadioKit.small_button(host, "Key", 24.0, 12)
	key_button.toggle_mode = true
	key_button.tooltip_text = "What the marks on the map mean"
	key_button.toggled.connect(func(on: bool): key_panel.visible = on)
	key_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(key_button)
	body.add_child(top)
	map_scroll = ScrollContainer.new()
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	map_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(map_scroll.get_h_scroll_bar())
	body.add_child(map_scroll)
	map = Map.new()
	map.setup(host)
	map.set_pin_focus(Control.FOCUS_NONE)
	map.place_chosen.connect(_on_pin_chosen)
	map.custom_minimum_size = Vector2(200, 120)
	map_scroll.add_child(map)
	key_panel = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Map.SHEET
	paper.border_color = Map.SHEET_EDGE
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(4)
	paper.content_margin_left = 8
	paper.content_margin_right = 8
	paper.content_margin_top = 5
	paper.content_margin_bottom = 5
	key_panel.add_theme_stylebox_override("panel", paper)
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_panel.add_child(Map.make_legend(host, host.PAPER_INK2))
	key_panel.visible = false
	body.add_child(key_panel)

	body.add_child(_build_card())
	body.add_child(_build_people())
	body.add_child(_build_ride())
	body.add_child(_build_actions())

	# the foot: who is out, and the way to the full page
	foot = host._vbox(4)
	foot.add_child(_rule())
	out_caption = host._caps("Out now", host.INK3)
	foot.add_child(out_caption)
	out_box = host._vbox(2)
	foot.add_child(out_box)
	var row: HBoxContainer = host._hbox(8)
	row.add_child(host._spacer())
	var full := RadioKit.small_button(host, "Full page", BUTTON_H, 13)
	full.tooltip_text = "The whole Town Board: the garrison of an outpost, the full card of every place\nKey: Shift+G"
	full.pressed.connect(full_page)
	row.add_child(full)
	buttons["full"] = full
	foot.add_child(row)
	body.add_child(foot)


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = host.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A wrapped line of the page: it asks for a little width so that it never folds into a column of letters.
func _para(text: String, size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = host._label(text, Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	return l


## The scroll bars in the panel's colours: a faint track and a chalk knob.
func _style_scrollbar(bar: ScrollBar) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(host.INK, 0.08)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	var knobs := {"grabber": Color(host.INK, 0.35), "grabber_highlight": Color(host.INK, 0.5), "grabber_pressed": Color(host.INK, 0.6)}
	for knob_name in knobs:
		var knob := StyleBoxFlat.new()
		knob.bg_color = knobs[knob_name]
		knob.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(knob_name, knob)
	bar.custom_minimum_size = Vector2(9, 9)


## A slip of the page: a board a little lighter than the panel with a thin chalk edge.
func _slip_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = host._flat(Color(host.PANEL_HI, 0.9), 6, host.LINE2, false)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 7
	s.content_margin_bottom = 8
	return s


## A small tag in capitals: `ink` on a faint dark wash with an edge of itself, a pill.
func _tag(text: String, ink: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.26)
	s.border_color = Color(ink, 0.6)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", s)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(host._caps(text, ink))
	return chip


## The card of the chosen place: made once, shown and filled as the choice changes.
func _build_card() -> PanelContainer:
	card = host._panel(_slip_style())
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var col: VBoxContainer = host._vbox(6)
	empty_label = _para("Nothing is chosen. Tap a pin on the map to see the place, what it may give and who would go.", 13, host.INK2)
	col.add_child(empty_label)
	place_view = host._vbox(6)
	name_label = host._label("", Fonts.cond(700), 20, host.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 100
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	place_view.add_child(name_label)
	kind_label = host._caps("", host.INK3)
	place_view.add_child(kind_label)
	tag_flow = HFlowContainer.new()
	tag_flow.add_theme_constant_override("h_separation", 6)
	tag_flow.add_theme_constant_override("v_separation", 3)
	tag_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_view.add_child(tag_flow)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the danger: three pips and the words
	var danger_value: HBoxContainer = host._hbox(6)
	pip_row = host._hbox(3)
	pip_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 3:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(9, 9)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
	danger_value.add_child(pip_row)
	var danger_words := _para("", 13, host.INK)
	danger_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	danger_value.add_child(danger_words)
	_fact(grid, "danger", "Danger", danger_value, danger_words)
	_fact(grid, "trip", "Trip", _para("", 13, host.INK))
	var loot_box: VBoxContainer = host._vbox(3)
	var loot_hint := _para("", 13, host.INK)
	loot_box.add_child(loot_hint)
	loot_chips = HFlowContainer.new()
	loot_chips.add_theme_constant_override("h_separation", 9)
	loot_chips.add_theme_constant_override("v_separation", 2)
	loot_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loot_box.add_child(loot_chips)
	_fact(grid, "loot", "Gives", loot_box, loot_hint)
	_fact(grid, "note", "Now", _para("", 13, host.WARN, 600))
	_fact(grid, "nest", "Nest", _para("", 13, host.INK))
	_fact(grid, "outpost", "Outpost", _para("", 13, host.INK))
	_fact(grid, "held", "Held by", _para("", 13, host.INK))
	place_view.add_child(grid)
	col.add_child(place_view)
	card.add_child(col)
	return card


## One line of the card's grid: a caption and what it says (`value` goes in the grid; `label` is the label that carries the words).
func _fact(grid: GridContainer, key: String, caption: String, value: Control, label: Label = null) -> void:
	var cap: Label = host._caps(caption, host.INK3)
	cap.custom_minimum_size.x = 54
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_child(cap)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	facts[key] = {"cap": cap, "value": value, "label": label if label != null else value}


## The people: who to ask, as chips that are ticked and unticked.
func _build_people() -> VBoxContainer:
	people_box = host._vbox(5)
	people_box.add_child(host._caps("Who goes", host.INK3))
	people_hint = _para("", 12, host.INK3)
	people_box.add_child(people_hint)
	chip_flow = HFlowContainer.new()
	chip_flow.add_theme_constant_override("h_separation", 6)
	chip_flow.add_theme_constant_override("v_separation", 6)
	chip_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	people_box.add_child(chip_flow)
	return people_box


## The ride: on foot, or in one of the vehicles that are parked (only there while one is).
func _build_ride() -> VBoxContainer:
	ride_box = host._vbox(5)
	var caption: HBoxContainer = host._hbox(8)
	caption.add_child(host._caps("Ride", host.INK3))
	ride_tip = host._label("", Fonts.sans(400), 12, host.INK3)
	ride_tip.size_flags_vertical = Control.SIZE_SHRINK_END
	caption.add_child(ride_tip)
	ride_box.add_child(caption)
	ride_flow = HFlowContainer.new()
	ride_flow.add_theme_constant_override("h_separation", 6)
	ride_flow.add_theme_constant_override("v_separation", 6)
	ride_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ride_box.add_child(ride_flow)
	ride_box.visible = false
	return ride_box


## The two ways to go, Claim and Recall, and the lines that say why anything is off.
func _build_actions() -> VBoxContainer:
	var col: VBoxContainer = host._vbox(6)
	var go: Button = host._button("Take control", true)
	go.custom_minimum_size = Vector2(0, 38)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.set_meta("look", true)
	go.pressed.connect(func(): act("go"))
	col.add_child(go)
	buttons["go"] = go
	go_note = _para("", 12, host.WARN, 600)
	go_note.visible = false
	col.add_child(go_note)
	stay_note = _para("", 12, host.WARN)
	stay_note.visible = false
	col.add_child(stay_note)
	night_note = _para("", 12, host.INK2, 600)
	night_note.visible = false
	col.add_child(night_note)
	col.add_child(_rule())

	var errand_row: HFlowContainer = HFlowContainer.new()
	errand_row.add_theme_constant_override("h_separation", 6)
	errand_row.add_theme_constant_override("v_separation", 4)
	errand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var errand_caption: Label = host._caps("Send them without you", host.INK3)
	errand_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	errand_row.add_child(errand_caption)
	for a in ERRANDS:
		var b := RadioKit.small_button(host, String(ERRAND_NAME[a]), 28.0, 13)
		b.custom_minimum_size.x = 54
		b.tooltip_text = String(ERRAND_TIP[a])
		b.pressed.connect(set_errand_action.bind(String(a)))
		errand_row.add_child(b)
		segments[String(a)] = b
	col.add_child(errand_row)
	var ask: Button = RadioKit.small_button(host, "Ask to go", 34.0, 14)
	ask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask.clip_text = true
	ask.pressed.connect(func(): act("errand", {"insist": insist_on}))
	col.add_child(ask)
	buttons["errand"] = ask
	summary_label = _para("", 12, host.INK3)
	summary_label.visible = false
	col.add_child(summary_label)
	terms_note = _para("", 12, host.INK3)
	terms_note.visible = false
	col.add_child(terms_note)
	refusal_box = host._vbox(2)
	col.add_child(refusal_box)
	var insist: Button = RadioKit.small_button(host, "Insist", 26.0, 13)
	insist.toggle_mode = true
	insist.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	insist.toggled.connect(func(on: bool): set_insist(on))
	insist.visible = false
	col.add_child(insist)
	buttons["insist"] = insist
	answer_label = _para("", 13, host.INK, 600)
	answer_label.visible = false
	col.add_child(answer_label)

	col.add_child(_rule())
	claim_row = HFlowContainer.new()
	claim_row.add_theme_constant_override("h_separation", 6)
	claim_row.add_theme_constant_override("v_separation", 4)
	claim_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for def in [["claim", "Claim"], ["recall", "Recall"]]:
		var b := RadioKit.small_button(host, String(def[1]), 30.0, 13)
		b.pressed.connect(func(): act(String(def[0])))
		claim_row.add_child(b)
		buttons[String(def[0])] = b
	col.add_child(claim_row)
	feedback_label = _para("", 13, host.INK, 600)
	feedback_label.visible = false
	col.add_child(feedback_label)
	return col


# ------------------------------------------------------------------ layout --

func _layout() -> void:
	if map == null or not is_inside_tree():
		return
	var avail := maxf(size.x, 120.0)
	# the sheet is as wide as the page and not much taller than it is wide (the page has more to show than a map); the pins are kept
	# apart (a town that has grown needs more room: the sheet then is wider than the page and scrolls sideways)
	var pad2: float = Map.PAD * 2.0
	var view: Rect2 = map.view
	var scale_w := (avail - pad2) / maxf(view.size.x, 1.0)
	var scale_cap := (maxf(MAP_MIN_H, avail * MAP_ASPECT) - pad2) / maxf(view.size.y, 1.0)
	var need := (float(map.width_for_clear_pins()) - pad2) / maxf(view.size.x, 1.0)
	var scale := maxf(minf(scale_w, scale_cap), need)
	scale = minf(scale, (MAP_MAX_W - pad2) / maxf(view.size.x, 1.0))
	var w := maxf(avail, scale * view.size.x + pad2)
	var h := scale * view.size.y + pad2
	map.custom_minimum_size = Vector2(w, h)
	map_scroll.custom_minimum_size = Vector2(0, h + (11.0 if w > avail + 0.5 else 0.0))
	_sheet = {"w": w, "h": h, "scale": scale, "view": view, "avail": avail}
	# a sheet wider than the page opens on the school (the town is round it), and goes back to it when the sheet changes size (a place
	# found, a new width)
	if size.x > 0.0 and absf(w - _centered_w) > 0.5:
		_centered_w = w
		_center_map.call_deferred("")


## Where a tile of the board is across the sheet (pixels from its left edge): the map centres what it shows in the sheet.
func _sheet_x(tile_x: float) -> float:
	if _sheet.is_empty():
		return 0.0
	var view: Rect2 = _sheet.view
	var scale: float = _sheet.scale
	return (float(_sheet.w) - view.size.x * scale) / 2.0 - view.position.x * scale + tile_x * scale


## Scrolls the frame of a sheet that is wider than the page to put the school (or the place `id`, unless it is in view already) in the
## middle of it.
func _center_map(id: String) -> void:
	if map_scroll == null or not is_inside_tree() or _sheet.is_empty():
		return
	await get_tree().process_frame
	if map_scroll == null or not is_inside_tree():
		return
	var frame_w := map_scroll.size.x
	var sheet_w: float = _sheet.w
	if sheet_w <= frame_w + 0.5:
		map_scroll.scroll_horizontal = 0
		return
	var tile_x: float = Vector2(sites[id].pos).x if id != "" and sites.has(id) else float(map.home.x)
	var at := _sheet_x(tile_x)
	var left := float(map_scroll.scroll_horizontal)
	if id != "" and at >= left + 24.0 and at <= left + frame_w - 24.0:
		return
	map_scroll.scroll_horizontal = int(clampf(at - frame_w / 2.0, 0.0, sheet_w - frame_w))


## The map's width and the height it asks for (for the tests).
func map_size() -> Vector2:
	return map.custom_minimum_size if map != null else Vector2.ZERO


# ----------------------------------------------------------------- the choices --

## Chooses a place (a known one): its pin is ringed in gold and the card shows it. False if it is not known.
func select_place(id: String) -> bool:
	if not sites.has(id):
		return false
	var changed := id != site_id
	site_id = id
	if changed:
		errand_action = _default_action(sites[id])
		insist_on = false
		_answer = {}
		_feedback = {"text": "", "level": "info"}
		_sound("ui_click")
	refresh(true)
	if changed:
		_reveal_card.call_deferred()
		_center_map.call_deferred(id)
	return true


## What the errand is at a place unless someone says otherwise: loot where there is something to take, else clear, else scout.
func _default_action(s: Dictionary) -> String:
	var actions: Array = s.get("actions", [])
	if actions.has("loot"):
		return "loot"
	if actions.has("clear"):
		return "clear"
	return "scout"


func _on_pin_chosen(id: String) -> void:
	select_place(id)


## The place that is chosen ("" when none).
func chosen() -> String:
	return site_id


## Opens the page on a place (what another page's "Show on the map" does).
func focus_on(id: String) -> void:
	select_place(id)


## Brings the card into view when the map is tall enough to push it off the bottom of the panel (the panel's own scroll, which holds this page).
func _reveal_card() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var n := get_parent()
	while n != null and not n is ScrollContainer:
		n = n.get_parent()
	if n != null:
		(n as ScrollContainer).ensure_control_visible(card)


## Sets what the errand does (Loot, Scout or Clear): false for anything else.
func set_errand_action(action: String) -> bool:
	if not ERRANDS.has(action):
		return false
	if action != errand_action:
		errand_action = action
		_answer = {}
		_sound("ui_click")
	refresh(true)
	return true


## Pushes (or stops pushing) the ticked people who refuse softly.
func set_insist(on: bool) -> void:
	if on != insist_on:
		insist_on = on
		_sound("ui_click")
	refresh(true)


## How many people a trip takes: three on foot, the seats of the vehicle that is chosen.
func party_limit() -> int:
	var s = _sim()
	if s == null:
		return 0
	return PlaceFlow.seats(s, vehicle_id)


## Ticks `p` (they are asked, or come along), or unticks them. A person who cannot be asked at all (down, away, gone: the radio's hard
## refusals) cannot be ticked; the party never holds more than the seats. True if the ticks changed.
func toggle_person(p) -> bool:
	if p == null or not chips.has(String(p.id)):
		return false
	var id := String(p.id)
	if ticks.has(id):
		ticks.erase(id)
		_after_tick()
		return true
	var st := _person_state(p)
	if st.kind == "hard" or st.kind == "queued":
		_say(String(st.why), "warn")
		_sound("ui_error")
		return false
	if ticks.size() >= party_limit():
		var s = _sim()
		var why := ""
		if vehicle_id != "":
			why = String(s.vehicles.why_not_use(vehicle_id, ticks.size() + 1, site_id))
		if why == "":
			why = "Three is the most on foot."
		_say(why, "warn")
		_sound("ui_error")
		return false
	ticks.append(id)
	_after_tick()
	return true


func _after_tick() -> void:
	_answer = {}
	_feedback = {"text": "", "level": "info"}
	_sound("ui_click")
	refresh(true)


## The people ticked, as Person objects (in the order they were ticked; those who are gone since are dropped).
func ticked_people() -> Array:
	var out: Array = []
	for id in ticks:
		if chips.has(String(id)):
			out.append(chips[String(id)].person)
	return out


## Chooses how the party goes: a parked vehicle's id, or "" for on foot. False if that vehicle is not parked (the page says so).
func choose_vehicle(id: String) -> bool:
	if id != "" and not _is_parked(id):
		_say("That vehicle is not at the gate.", "warn")
		return false
	if id == vehicle_id:
		return true
	vehicle_id = id
	# the seats of the new way: the last of those ticked are let go of
	while ticks.size() > party_limit() and not ticks.is_empty():
		ticks.pop_back()
	_answer = {}
	_sound("ui_click")
	refresh(true)
	return true


func _is_parked(id: String) -> bool:
	var s = _sim()
	if s == null:
		return false
	for v in s.vehicles.parked():
		if String(v.id) == id:
			return true
	return false


func _ride_name(id: String) -> String:
	var s = _sim()
	return String(s.vehicles.name_of(id)).to_lower() if s != null and id != "" else ""


func _sound(sound_name: String) -> void:
	if host != null and host.has_method("ui_sound"):
		host.ui_sound(sound_name)


func _say(text: String, level: String) -> void:
	_feedback = {"text": text, "level": level}
	_refresh_feedback()


# ----------------------------------------------------------------- the people --

## Whether the radio would send this person on an errand, and why not: {"ok", "why" (the radio's own words), "hard"}. It is
## `radio.errand_willingness` (the same list as the verbs' `reason_not(p, "go")`, and the trip's rules for who can be taken at all:
## someone the rules will not take is a hard refusal whatever they say), asked of the place that is chosen. Inside `refresh` it is asked
## once for everyone at the base (`_everyone_asked`); a person alone is asked when the page is not refreshing.
func _reason_go(p) -> Dictionary:
	var radio = _radio()
	if radio == null:
		return {"ok": false, "why": "Nobody is on the radio", "hard": true}
	var w: Dictionary = _everyone_asked() if _memoizing else radio.errand_willingness([p], site_id, errand_action, vehicle_id)
	if (w.going as Array).has(p):
		return {"ok": true, "why": "", "hard": false}
	for r in w.refused:
		if String(r.id) == String(p.id):
			return {"ok": false, "why": String(r.why), "hard": bool(r.hard)}
	return radio.reason_not(p, "go")


## The radio's answer for everyone at the base at once (worked out once for each refresh).
func _everyone_asked() -> Dictionary:
	if not _memo.has("asked"):
		_memo["asked"] = _radio().errand_willingness(_candidates(), site_id, errand_action, vehicle_id, ticks)    # (company is judged against the party ticked)
	return _memo["asked"]


## The errand that waits for `p` (the radio's `errand_wait` entry), or {}.
func _waiting_errand_of(p) -> Dictionary:
	var radio = _radio()
	if radio == null or radio.get("errand_wait") == null:
		return {}
	for e in radio.errand_wait:
		if (e.get("ids", []) as Array).has(String(p.id)):
			return e
	return {}


## What a person is as a choice: {"kind": "willing" | "soft" | "hard" | "queued", "text" (the short word under the name), "why" (the whole
## refusal: the radio's own words, "" when willing)}. Inside `refresh` the radio is asked once for everybody at the base.
func _person_state(p) -> Dictionary:
	var waiting := _waiting_errand_of(p)
	if not waiting.is_empty():
		var where := _place_name(String(waiting.get("place", "")))
		return {"kind": "queued", "text": "setting off", "why": "%s is setting off for %s" % [String(p.first), where]}
	var r := _reason_go(p)
	if bool(r.ok):
		return {"kind": "willing", "text": "willing", "why": ""}
	return {"kind": "hard" if bool(r.get("hard", false)) else "soft", "text": _short_reason(p, String(r.why)), "why": String(r.why)}


## "tending a patient, can't go" from "Ana: tending a patient, can't go"; "down" from "Dez is down".
func _short_reason(p, why: String) -> String:
	var first := String(p.first)
	for prefix in [first + ": ", first + " is ", first + " has ", first + " "]:
		if why.begins_with(prefix):
			return why.trim_prefix(prefix)
	return why


func _place_name(id: String) -> String:
	var s = _sim()
	if s == null or id == "":
		return ""
	return String(s.town.place(id).get("name", id))


## Who is on offer: everyone at the base but the player, the dead and the turned left out.
func _candidates() -> Array:
	var out: Array = []
	var s = _sim()
	if s == null:
		return out
	var me = _avatar()
	for p in s.people:
		if p == me or p.dead or p.turned or bool(p.player):
			continue
		out.append(p)
	return out


## The chips are made again only when the people are not the same; each is kept in line with the person's state.
func _refresh_people() -> void:
	var people := _candidates()
	var sig := ""
	for p in people:
		sig += "%s;" % p.id
	if sig != _people_sig:
		_people_sig = sig
		for c in chip_flow.get_children():
			chip_flow.remove_child(c)
			c.queue_free()
		chips.clear()
		for p in people:
			chip_flow.add_child(_person_chip(p))
	# a tick of someone who is not a choice any more (down, away, gone, setting off) is let go
	var keep: Array = []
	for id in ticks:
		if not chips.has(String(id)):
			continue
		var st := _person_state(chips[String(id)].person)
		if st.kind == "hard" or st.kind == "queued":
			continue
		keep.append(id)
	ticks = keep
	for id in chips:
		var e: Dictionary = chips[id]
		var p = e.person
		var st := _person_state(p)
		var is_ticked: bool = ticks.has(String(id))
		var disabled: bool = st.kind == "hard" or st.kind == "queued"
		var b: Button = e.chip
		b.disabled = disabled
		b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
		_style_chip(b, is_ticked, String(st.kind))
		e.tick.visible = is_ticked
		var ink: Color = host.OK if st.kind == "willing" else (host.WARN if st.kind == "soft" else host.INK3)
		if e.status.get_theme_color("font_color") != ink:
			e.status.add_theme_color_override("font_color", ink)
		if e.status.text != String(st.text):
			e.status.text = String(st.text)
		e.pic.modulate = Color(1, 1, 1, 0.45 if disabled else 1.0)
		var first := String(p.first)
		var tip := ""
		if disabled:
			tip = String(st.why)
		elif st.kind == "soft":
			tip = "%s\n%s asks for a push: tick them and Insist, at a cost of trust." % [String(st.why), first]
		elif is_ticked:
			tip = "%s is going. Tap to leave %s at home." % [first, "them"]
		else:
			tip = "Tap to bring %s along, or to ask %s to go." % [first, "them"]
		if b.tooltip_text != tip:
			b.tooltip_text = tip
	var any := not people.is_empty()
	people_hint.visible = true
	if not any:
		people_hint.text = "Nobody else is at the base."
	else:
		var most := party_limit()
		people_hint.text = "Tap a face to bring them or ask them. %s" % ("Three is the most." if vehicle_id == "" else "The %s seats %d." % [_ride_name(vehicle_id), most])


## A person's chip: a face, a first name and the word under it.
func _person_chip(p) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	var row: HBoxContainer = host._hbox(6)
	var pic := TextureRect.new()
	pic.texture = host.portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(32, 32)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var text: VBoxContainer = host._vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l: Label = host._label(String(p.first), Fonts.cond(700), 15, host.INK)
	name_l.clip_text = true
	name_l.custom_minimum_size.x = 10
	text.add_child(name_l)
	var status: Label = host._label("", Fonts.sans(400), 12, host.INK3)
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.custom_minimum_size.x = 10
	text.add_child(status)
	row.add_child(text)
	pad.add_child(row)
	b.add_child(pad)
	var tick := TickMark.new()
	tick.visible = false
	b.add_child(tick)
	b.set_meta("person", String(p.id))
	b.pressed.connect(func(): toggle_person(p))
	chips[String(p.id)] = {"chip": b, "pic": pic, "name": name_l, "status": status, "tick": tick, "person": p}
	_style_chip(b, false, "willing")
	return b


## The look of a chip: a card a shade darker than the panel with a chalk edge; gold-washed and heavier while the person is ticked;
## amber-edged for a soft refusal. (Darker, not lighter: the words on it keep their contrast on the lit panel.)
func _style_chip(b: Button, ticked: bool, kind: String) -> void:
	var key := "%d|%s" % [int(ticked), kind]
	if b.has_meta("sk") and String(b.get_meta("sk")) == key:
		return
	b.set_meta("sk", key)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0.24)
		s.border_color = host.LINE2
		if kind == "soft":
			s.border_color = Color(host.WARN, 0.8)
		if ticked:
			s.bg_color = Color(0.1, 0.07, 0.0, 0.34)
			s.border_color = host.ACCENT
		if state == "hover" and not ticked:
			s.bg_color = Color(0, 0, 0, 0.14)
		elif state == "pressed":
			s.bg_color = Color(0, 0, 0, 0.36)
		elif state == "disabled":
			s.bg_color = Color(0, 0, 0, 0.3)
			s.border_color = host.LINE
		s.set_border_width_all(2 if ticked else 1)
		s.set_corner_radius_all(6)
		s.anti_aliasing = true
		b.add_theme_stylebox_override(state, s)


# --------------------------------------------------------------------- refresh --

## Brings the page in line with the game: the pins, the card, the people, the ride, the buttons, the foot. Safe at any time. The panel
## calls it ten times a second while the page is open; `force` is for the page's own changes (it redraws what a choice changes).
func refresh(force: bool = false) -> void:
	if not _built:
		return
	var on := _on()
	message_label.visible = not on
	body.visible = on
	if not on:
		return
	_memo.clear()
	_memoizing = true
	_expire_answer()
	_sync_sites(force)
	_refresh_map(force)
	_refresh_card(force)
	_refresh_people()
	_refresh_ride(force)
	_refresh_actions()
	_refresh_foot()
	_memoizing = false
	_memo.clear()


## The places as the board offers them: asked again when the clock, a place or the stores have moved.
func _sync_sites(force: bool) -> void:
	var s = _sim()
	var sig := "%d|%s|%d|" % [floori(float(s.clock_min) / 5.0), String(s.phase), int(float(s.stock.scrap))]
	for id in s.town.state:
		var st: Dictionary = s.town.state[id]
		sig += "%s:%d%d%d%d:%s;" % [id, int(bool(st.known)), int(bool(st.cleared)), int(bool(st.claimed)), int(bool(st.rescued)), ",".join(s.town.garrison_of(id))]
	for party_out in s.scavenge.parties:
		sig += "p%d:%s:%d;" % [int(party_out.n), String(party_out.state), int(float(party_out.return_at))]
	if sig == _sites_sig and not force and not sites.is_empty():
		return
	_sites_sig = sig
	sites = {}
	for site in s.scavenge.available_sites():
		sites[String(site.id)] = site
	if site_id != "" and not sites.has(site_id):
		site_id = ""
		_answer = {}


func _refresh_map(force: bool) -> void:
	var s = _sim()
	var sig := "%s|%s|%d|" % [site_id, _sites_sig, s.scavenge.parties.size()]
	if sig == _map_sig and not force:
		return
	_map_sig = sig
	map.set_data(MapData.build(s, site_id, _departures, _routes))
	_layout()


## "bus depot" from "bus_depot".
static func _kind_text(kind: String) -> String:
	return kind.replace("_", " ")


func _fact_set(key: String, text: String, shown: bool = true) -> void:
	var f: Dictionary = facts[key]
	f.cap.visible = shown
	f.value.visible = shown
	if f.label.text != text:
		f.label.text = text


func _refresh_card(force: bool) -> void:
	var has := site_id != "" and sites.has(site_id)
	var s: Dictionary = sites.get(site_id, {})
	var sim = _sim()
	var sig := "%s|%s|%s|%s|%d|%d" % [site_id, str(s.hash()), vehicle_id, errand_action, floori(float(sim.clock_min) / 5.0), int(float(sim.stock.scrap))]
	if sig == _card_sig and not force:
		return
	_card_sig = sig
	empty_label.visible = not has
	place_view.visible = has
	if not has:
		return
	var state := String(s.state)
	name_label.text = String(s.name)
	name_label.tooltip_text = String(s.get("blurb", ""))
	kind_label.text = _kind_text(String(s.get("kind", ""))).to_upper()
	kind_label.visible = kind_label.text != ""
	for c in tag_flow.get_children():
		tag_flow.remove_child(c)
		c.queue_free()
	var gone := state == "cleared" or state == "claimed"
	if state == "cleared":
		tag_flow.add_child(_tag("Cleared", host.OK))
	elif state == "claimed":
		tag_flow.add_child(_tag("Your outpost", host.ACCENT))
	var strength := int(s.get("nest", {}).get("strength", 0)) if s.get("nest", {}) is Dictionary else 0
	if strength > 0 and not gone:
		tag_flow.add_child(_tag("Nest %d" % strength, host.DANGER_TEXT))
	if bool(s.get("survivor", false)):
		var hiding_tag := _tag("Someone hiding", host.INFO)
		hiding_tag.tooltip_text = "Someone is hiding here: a rescue may come home with a party."
		hiding_tag.mouse_filter = Control.MOUSE_FILTER_PASS
		tag_flow.add_child(hiding_tag)
	if bool(s.get("needs_vehicle", false)):
		tag_flow.add_child(_tag("By vehicle only", host.INFO))
	var until := MapData.picked_over_until(String(s.get("note", "")))
	if until > 0:
		tag_flow.add_child(_tag("Picked over until day %d" % until, host.WARN))
	tag_flow.visible = tag_flow.get_child_count() > 0
	# the danger
	var danger := clampi(int(s.get("danger", 1)), 0, 3)
	var shown_danger := 0 if gone else danger
	for i in 3:
		var pip: Panel = pip_row.get_child(i)
		var st := StyleBoxFlat.new()
		st.bg_color = (host.DANGER_TEXT if shown_danger >= 3 else host.WARN) if i < shown_danger else Color(host.INK, 0.2)
		st.set_corner_radius_all(5)
		st.anti_aliasing = true
		pip.add_theme_stylebox_override("panel", st)
	_fact_set("danger", "None left: the dead are gone" if gone else String(MapData.DANGER_WORDS[danger]))
	pip_row.tooltip_text = "Danger %d of 3" % shown_danger
	pip_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_fact_set("trip", trip_text(s))
	# what it may give
	_fact_set("loot", String(s.get("loot_hint", "")))
	for c in loot_chips.get_children():
		loot_chips.remove_child(c)
		c.queue_free()
	var loot = s.get("loot", {})
	var extra = s.get("extra", {})
	if loot is Dictionary:
		for k in MapData.LOOT_ORDER:
			if loot.has(k):
				loot_chips.add_child(_loot_chip(k, MapData.range_text(loot[k]), host.INK))
		if extra is Dictionary:
			for k in MapData.LOOT_ORDER:
				if extra.has(k):
					loot_chips.add_child(_loot_chip(k, "sometimes", host.INK3))
	loot_chips.visible = loot_chips.get_child_count() > 0
	var note := String(s.get("note", ""))
	_fact_set("note", note, note != "" and state != "claimed")
	var nest_strength := int(sim.town.nest_strength(site_id))
	if nest_strength > 0 and not gone:
		_fact_set("nest", "Strength %d. %s" % [nest_strength, _nest_lean(site_id)])
	elif nest_strength > 0:
		_fact_set("nest", "Gone: the nights are quieter for it.")
	else:
		_fact_set("nest", "", false)
	var outpost: Dictionary = s.get("outpost", {}) if s.get("outpost", {}) is Dictionary else {}
	if outpost.is_empty():
		_fact_set("outpost", "", false)
	elif state == "claimed":
		_fact_set("outpost", "Yours: %s a day. Empty, it can be overrun at night." % MapData.yield_text(outpost.get("yield", {})))
	elif state == "cleared":
		_fact_set("outpost", "Can be claimed: %s a day, for %d scrap." % [MapData.yield_text(outpost.get("yield", {})), int(outpost.get("cost", 0))])
	else:
		_fact_set("outpost", "Once cleared: %s a day, for %d scrap." % [MapData.yield_text(outpost.get("yield", {})), int(outpost.get("cost", 0))])
	var holders := _garrison_names(s.get("garrison", []))
	_fact_set("held", holders if holders != "" else "Nobody. It is unguarded.", state == "claimed")


func _loot_chip(stock: String, text: String, color: Color) -> Control:
	var row: HBoxContainer = host._hbox(3)
	var ic: TextureRect = host._icon(stock, 14, host.INK2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(host._label(text, Fonts.cond(600), 14, color))
	row.tooltip_text = String(MapData.LOOT_NAME.get(stock, stock))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _nest_lean(id: String) -> String:
	var s = _sim()
	var spawns: Array = s.spawns
	if spawns.is_empty():
		return "The nights lean this way."
	var idx: int = s.town.heading_of(s.town.place(id))
	return "The nights lean to the %s." % Waves.direction_name(spawns[clampi(idx, 0, spawns.size() - 1)])


func _garrison_names(ids: Array) -> String:
	var s = _sim()
	var list: Array = []
	for pid in ids:
		for p in s.people:
			if String(p.id) == String(pid):
				list.append(String(p.first))
	return MapData.join(list)


## The trip in words, for the place `s` as it is offered: the hours on foot and by the chosen vehicle (for what the errand is), and when
## the party would be back ("Back tomorrow: a night out, and no one on the wall").
func trip_text(s: Dictionary) -> String:
	var sim = _sim()
	var scav = sim.scavenge
	var id := String(s.get("id", ""))
	var needs := bool(s.get("needs_vehicle", false))
	var lines: Array = []
	var hours := 0.0
	if needs:
		lines.append("On foot: too far to walk, it takes a vehicle.")
	else:
		hours = scav.action_hours(id, errand_action, "")
		lines.append("On foot: %s there and back." % Map.hours_text(hours))
	if vehicle_id != "":
		hours = scav.action_hours(id, errand_action, vehicle_id)
		lines.append("By the %s: %s there and back (%s fuel)." % [_ride_name(vehicle_id), Map.hours_text(hours), MapData.num(sim.vehicles.fuel_for(id, vehicle_id))])
	if needs and vehicle_id == "":
		return "\n".join(lines)
	var start := clampf(float(sim.hour), MapData.FIRST_LIGHT_H, MapData.LEAVE_BY_H) if scav.can_send() else 7.0
	var back := start + hours
	if back >= float(sim.seasons.dusk_hour()):
		lines.append("Back tomorrow: a night out, and no one on the wall.")
	else:
		lines.append("Back about %s." % MapData.clock_text(back))
	return "\n".join(lines)


## The vehicles: "On foot" and a chip for each one that is parked, with what the trip to the chosen place takes of each.
func _refresh_ride(force: bool) -> void:
	var s = _sim()
	var parked: Array = s.vehicles.parked()
	ride_box.visible = not parked.is_empty()
	if parked.is_empty():
		if not ride_chips.is_empty():
			for c in ride_flow.get_children():
				ride_flow.remove_child(c)
				c.queue_free()
			ride_chips.clear()
		_ride_sig = ""
		if vehicle_id != "":
			vehicle_id = ""
		return
	if vehicle_id != "" and not _is_parked(vehicle_id):
		vehicle_id = ""
	var site: Dictionary = sites.get(site_id, {})
	var entries := MapData.ride_entries(s, site, ticks.size(), errand_action)
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
			ride_flow.add_child(_ride_chip(e))
	for e in entries:
		var entry: Dictionary = ride_chips.get(String(e.id), {})
		if entry.is_empty():
			continue
		var is_chosen: bool = String(e.id) == vehicle_id
		_style_chip(entry.chip, is_chosen, "willing")
		var tip := String(e.tip)
		entry.chip.tooltip_text = ("%s\nGoing this way." % tip) if is_chosen else ("%s\nTap to go this way." % tip)
	ride_tip.text = "The tank has %s fuel." % MapData.num(float(s.vehicles.fuel))


func _ride_chip(e: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(RIDE_W, 56)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	var text: VBoxContainer = host._vbox(0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_l: Label = host._label(String(e.name), Fonts.cond(700), 15, host.INK)
	text.add_child(name_l)
	var warn_ink: Color = host.WARN if bool(e.warn) else host.INK2
	var l2: Label = host._label(String(e.l2), Fonts.sans(400 if not bool(e.warn) else 600), 12, warn_ink)
	l2.clip_text = true
	l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l2.custom_minimum_size.x = 10
	text.add_child(l2)
	var l3: Label = host._label(String(e.l3), Fonts.sans(400), 12, host.WARN if String(e.l3) == "Too far to walk" else host.INK2)
	l3.clip_text = true
	l3.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l3.custom_minimum_size.x = 10
	l3.visible = String(e.l3) != ""
	text.add_child(l3)
	pad.add_child(text)
	b.add_child(pad)
	var id := String(e.id)
	b.pressed.connect(func(): choose_vehicle(id))
	b.set_meta("vehicle", id)
	ride_chips[id] = {"chip": b, "name": name_l, "l2": l2, "l3": l3}
	_style_chip(b, false, "willing")
	return b


# ---------------------------------------------------------------- the reasons --

## The people the player takes on a played trip and who stays, as the colony will sort them out (`PlaceFlow.pick_party`: who will be asked
## and says no, and who does not fit): {"going": [the avatar, then those who come], "refused": [{"p", "why"}], "left_out": [{"p", "why"}]}.
func picked() -> Dictionary:
	if _memoizing:
		if not _memo.has("picked"):
			_memo["picked"] = PlaceFlow.pick_party(_sim(), ticked_people(), vehicle_id)
		return _memo["picked"]
	return PlaceFlow.pick_party(_sim(), ticked_people(), vehicle_id)


## The action a played trip is sent as: looting, or clearing when there is nothing here to take but the dead.
func played_action() -> String:
	var s: Dictionary = sites.get(site_id, {})
	return "loot" if (s.get("actions", []) as Array).has("loot") else "clear"


## Why the player cannot take control of a trip to the chosen place now ("" when they can): the words of a played trip's rules
## (`scavenge.why_not_played`) for the player and those who would come.
func _why_not_played() -> String:
	var sim = _sim()
	var s: Dictionary = sites.get(site_id, {})
	var who: Array = picked().going
	var why: String = sim.scavenge.why_not_played(who, site_id, played_action(), vehicle_id)
	if why == "Picked over." and String(s.get("note", "")) != "":
		return String(s.note)
	return why


## The errand as the page will ask it: what `radio.errand_willingness` says of the people ticked, and whether the button can be pressed.
## {"people", "ok", "why", "going", "refused", "soft" (the refusals that can be pushed), "pressable", "note", "names"}. A person who refuses
## softly and whom the player pushes (`insist_on`) goes too. The button is off, with the reason, when the TRIP is refused (the hour, the
## dead at the gate, the seats, the place) or nobody would go; it is NOT off when the only reason is people who can be pushed.
func errand_view() -> Dictionary:
	if _memoizing:
		if not _memo.has("view"):
			_memoizing = false
			_memo["view"] = errand_view()
			_memoizing = true
		return _memo["view"]
	var out := {"people": ticked_people(), "ok": false, "why": "", "going": [], "refused": [], "soft": [], "pressable": false, "note": "", "names": ""}
	if site_id == "":
		out.why = "Pick a place on the map first."
		return out
	var radio = _radio()
	if radio == null or radio.leader() == null:
		out.why = "Nobody is on the radio: there is nobody to ask."
		return out
	var people: Array = out.people
	var probe: Array = people if not people.is_empty() else _candidates()
	if probe.is_empty():
		out.why = "Nobody is at the base to ask."
		return out
	var w: Dictionary = radio.errand_willingness(probe, site_id, errand_action, vehicle_id)
	out.note = String(w.get("loot_note", ""))
	if people.is_empty():
		out.why = "Tick who you would ask to go: tap their faces."
		return out
	out.going = w.get("going", [])
	out.refused = w.get("refused", [])
	for r in out.refused:
		if not bool(r.get("hard", false)):
			out.soft.append(r)
	if bool(w.ok):
		out.ok = true
		out.pressable = true
		var asked: Array = (out.going as Array).duplicate()
		if insist_on:
			asked.append_array(_soft_people(out))
		out.names = MapData.names(asked)
		return out
	# not agreed: the trip is refused for those who would go, or nobody would go
	if not (out.going as Array).is_empty():
		out.why = String(w.why)
		return out
	var soft_people := _soft_people(out)
	if soft_people.is_empty() or String(_scav().why_not_when()) != "":
		out.why = String(w.why)
		return out
	# only people stand in the way, and they can be pushed: the trip must take them
	var trip_why := String(_scav().why_not_errand(soft_people, site_id, errand_action, vehicle_id, true))
	if trip_why != "":
		out.why = trip_why
		return out
	if insist_on:
		out.names = MapData.names(soft_people)
		out.pressable = true
		return out
	out.why = String(w.why)
	return out


func _scav():
	var s = _sim()
	return s.scavenge if s != null else null


func _person_by_id(id: String):
	var s = _sim()
	for p in s.people:
		if String(p.id) == id:
			return p
	return null


## Why `action` cannot be done now ("" when it can): "go" (Take control), "errand" (Ask to go), "claim", "recall".
func reason_for(action: String) -> String:
	var s = _sim()
	if s == null or not _on():
		return "There is no map in this game."
	if site_id == "" or not sites.has(site_id):
		return "Pick a place on the map first."
	var site: Dictionary = sites[site_id]
	match action:
		"go":
			if host == null or not host.get("on_raid") is Callable or not (host.on_raid as Callable).is_valid():
				return "Not in this game."
			if _avatar() == null:
				return "Nobody is on the radio: there is nobody to play."
			return _why_not_played()
		"errand":
			var v := errand_view()
			return "" if bool(v.pressable) else String(v.why)
		"claim":
			if String(site.state) == "claimed":
				return "It is already your outpost."
			if String(site.state) != "cleared":
				return "Clear it first: the dead have to be gone."
			var cost := int(site.get("outpost", {}).get("cost", 0))
			if float(s.stock.scrap) < float(cost):
				return "It takes %d scrap and the stores have %d." % [cost, int(float(s.stock.scrap))]
			return ""
		"recall":
			if (site.get("garrison", []) as Array).is_empty():
				return "Nobody is stationed there."
			return String(s.town.why_not_recall(site_id))
	return "That cannot be done."


# ----------------------------------------------------------------------- acting --

## Does `action` at the chosen place: "go" (take control of a trip), "errand" (ask the ticked people to go without you: `args.insist`
## pushes those who refuse softly), "claim" or "recall". {"ok", "why" ("" when it was done), "line" (what was said or done)}; the page
## says it too, under the buttons.
func act(action: String, args: Dictionary = {}) -> Dictionary:
	var why := reason_for(action)
	if why != "":
		_say(why, "warn")
		_sound("ui_error")
		return {"ok": false, "why": why, "line": ""}
	match action:
		"go":
			return _play()
		"errand":
			return _errand(args)
		"claim":
			var s = _sim()
			var where := String(sites[site_id].name)
			if not s.town.claim(site_id):
				_say("It cannot be claimed.", "warn")
				_sound("ui_error")
				return {"ok": false, "why": "It cannot be claimed.", "line": ""}
			_sound("ui_confirm")
			refresh(true)
			_say("%s is yours now." % where, "ok")
			return {"ok": true, "why": "", "line": "%s is yours now." % where}
		"recall":
			var s2 = _sim()
			var where2 := String(sites[site_id].name)
			var crew: Array = (sites[site_id].get("garrison", []) as Array).duplicate()
			var who: Array = []
			for pid in crew:
				var q = _person_by_id(String(pid))
				if q != null:
					who.append(q)
			s2.town.recall(site_id)
			_sound("ui_confirm")
			refresh(true)
			var line := "%s is on the way home from %s." % [MapData.names(who), where2] if not who.is_empty() else "Nobody was there."
			_say(line, "ok")
			return {"ok": true, "why": "", "line": line}
	return {"ok": false, "why": "That cannot be done.", "line": ""}


## Takes control of the trip (what the Town Board's Take control does): `host.on_raid` asks the people over the radio, begins the trip and
## plays the road, the place and the road home. The page's panel closes when it opened (a toast of the HUD says why when it did not).
func _play() -> Dictionary:
	var s = _sim()
	var going: Array = ticked_people()
	var place: Dictionary = s.town.place(site_id).duplicate(true)
	place["id"] = site_id
	# a place that has been cleared has few of the dead left (the dice zero its danger and nest too)
	if s.town.state_of(site_id) == "cleared" or s.town.state_of(site_id) == "claimed":
		place["cleared"] = true
	var penalty: float = s.scavenge.raid_penalty(site_id)
	var done := func(_result: Dictionary) -> void:
		pass
	var scene = host.on_raid.call(going, place, vehicle_id, penalty, done)
	if scene == null:
		_say("The trip could not begin.", "warn")
		_sound("ui_error")
		return {"ok": false, "why": "The trip could not begin.", "line": ""}
	_sound("ui_confirm")
	ticks.clear()
	if host.has_method("close_radio"):
		host.close_radio()
	return {"ok": true, "why": "", "line": "You take control."}


## Asks the people ticked to go without the player (`radio.request_errand`). They are queued by the radio and set off after their delay.
func _errand(args: Dictionary) -> Dictionary:
	var radio = _radio()
	var view := errand_view()
	var people: Array = view.people
	var res: Dictionary = radio.request_errand(people, site_id, errand_action, vehicle_id, args)
	var going: Array = res.get("going", [])
	var refused: Array = res.get("refused", [])
	_answer = {"ok": bool(res.get("ok", false)), "line": String(res.get("line", "")), "why": String(res.get("why", "")), "going": going, "refused": refused,
		"delay_s": float(res.get("delay_s", 0.0)), "at": Time.get_ticks_msec()}
	if bool(res.get("ok", false)):
		_sound("ui_confirm")
		# the people who agreed are queued: they are no longer ticked
		for q in going:
			ticks.erase(String(q.id))
		insist_on = false
	else:
		_sound("ui_error")
	refresh(true)
	return {"ok": bool(res.get("ok", false)), "why": String(res.get("why", "")), "line": String(res.get("line", ""))}


## Gives the answer up after a while (it has been read).
func _expire_answer() -> void:
	if not _answer.is_empty() and float(Time.get_ticks_msec() - int(_answer.at)) / 1000.0 > ANSWER_S:
		_answer = {}


# ------------------------------------------------------------------- the actions --

func _refresh_actions() -> void:
	var s = _sim()
	var site: Dictionary = sites.get(site_id, {})
	var has := not site.is_empty()
	var avatar = _avatar()
	var on_raid_ok: bool = host != null and host.get("on_raid") is Callable and (host.on_raid as Callable).is_valid()

	# Take control
	var go: Button = buttons.go
	var go_why := reason_for("go")
	go.disabled = go_why != ""
	_set_look(go, go_why == "")
	go.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if go_why != "" else Control.CURSOR_POINTING_HAND
	var go_tip := go_why
	if go_why == "" and has:
		var minutes: float = s.scavenge.road_minutes(site_id, vehicle_id)
		go_tip = "Play the trip yourself: you and your people go, you walk the road (about %d minutes, the base runs on meanwhile), search what you can, shoot what you must, and get out." % int(roundf(minutes))
	go.tooltip_text = go_tip
	go_note.visible = go_why != "" and has
	if go_note.visible:
		go_note.text = go_why
	# tonight, for the trip as it is planned (round 19, the avatar's page: the scavenging module's own words, as the Town Board's "Tonight" row
	# has them): when the night is a Big one, the hour to leave the place by; amber when the trip cannot be home in time
	var warning: Dictionary = NightKit.warning_line(s, site_id, vehicle_id, float(s.town.SEARCH_H)) if has else {}
	night_note.visible = not warning.is_empty()
	if night_note.visible:
		night_note.text = String(warning.text)
		night_note.add_theme_color_override("font_color", host.WARN if String(warning.tone) == "warn" else host.INK2)
	# who would stay behind: they say no, or the seats are full (the colony's own sorting, `PlaceFlow.pick_party`)
	var stay_lines: Array = []
	if avatar != null and not ticks.is_empty():
		stay_lines = PlaceFlow.refusal_lines(picked())
	stay_note.visible = not stay_lines.is_empty()
	if stay_note.visible:
		stay_note.text = "\n".join(stay_lines.map(func(l): return "%s (stays behind)" % String(l).trim_suffix(".")))

	# the errand: the switch, the button, the terms, the refusals
	for a in segments:
		var seg: Button = segments[a]
		_style_segment(seg, String(a) == errand_action)
		seg.tooltip_text = String(ERRAND_TIP[a])
	var view := errand_view()
	var ask: Button = buttons.errand
	var ask_why: String = "" if bool(view.pressable) else String(view.why)
	ask.disabled = ask_why != ""
	ask.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if ask_why != "" else Control.CURSOR_POINTING_HAND
	var names := String(view.names)
	ask.text = ("Ask %s to go" % names) if names != "" else "Ask to go"
	var ask_tip := ask_why
	if ask_why == "" and has:
		var where := String(site.name)
		match errand_action:
			"scout":
				ask_tip = "Ask %s over the radio to scout the way to %s without you. They set off after their delay." % [names, where]
			"clear":
				ask_tip = "Ask %s over the radio to clear %s without you. They set off after their delay, and a failed attempt hurts." % [names, where]
			_:
				ask_tip = "Ask %s over the radio to search %s without you. They set off after their delay, and come back with less." % [names, where]
	elif ask_why != "" and not (view.soft as Array).is_empty() and not insist_on:
		ask_tip += "\nInsist pushes those who refuse, at a cost of trust."
	ask.tooltip_text = ask_tip
	terms_note.visible = String(view.note) != "" and has
	if terms_note.visible:
		terms_note.text = String(view.note)
	# the refusals of those ticked (the radio's own lines) and Insist
	var lines: Array = []
	for r in view.refused:
		lines.append(String(r.why))
	_set_lines(refusal_box, lines, host.WARN)
	var insist: Button = buttons.insist
	insist.visible = not (view.soft as Array).is_empty()
	if not insist.visible and insist_on:
		insist_on = false
	insist.set_pressed_no_signal(insist_on)
	insist.text = "Insisting" if insist_on else "Insist"
	var cost: float = float(_radio().INSIST_COST) if _radio() != null else 6.0
	insist.tooltip_text = "Push %s to go anyway: it costs their trust (%d each) and their mood, and they go grudgingly." % [MapData.names(_soft_people(view)), int(cost)]
	if insist.visible:
		_style_segment(insist, insist_on)
	# why the button is off, in words under it (a prompt while nobody is ticked, an amber refusal otherwise)
	summary_label.visible = ask_why != "" and has
	if summary_label.visible:
		summary_label.text = ask_why
		summary_label.add_theme_color_override("font_color", host.INK3 if (view.people as Array).is_empty() else host.WARN)
	_refresh_answer()

	# Claim and Recall
	var state := String(site.get("state", ""))
	var has_outpost: bool = site.get("outpost", {}) is Dictionary and not (site.get("outpost", {}) as Dictionary).is_empty()
	var claim: Button = buttons.claim
	claim.visible = has and has_outpost and state != "claimed"
	var claim_why := reason_for("claim") if claim.visible else ""
	claim.disabled = claim_why != ""
	var cost_of_claim := int(site.get("outpost", {}).get("cost", 0)) if has_outpost else 0
	claim.text = "Claim for %d scrap" % cost_of_claim if has_outpost else "Claim"
	if claim_why != "":
		claim.tooltip_text = claim_why
	elif has_outpost:
		claim.tooltip_text = "Make %s your outpost: %d scrap now, then %s a day." % [String(site.get("name", "")), cost_of_claim, MapData.yield_text(site.get("outpost", {}).get("yield", {}))]
	else:
		claim.tooltip_text = "Claim the place as an outpost."
	var recall: Button = buttons.recall
	recall.visible = has and state == "claimed" and not (site.get("garrison", []) as Array).is_empty()
	var recall_why := reason_for("recall") if recall.visible else ""
	recall.disabled = recall_why != ""
	recall.tooltip_text = recall_why if recall_why != "" else "Call the garrison of %s home to the gate." % String(site.get("name", ""))
	for b in [claim, recall]:
		b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if b.disabled else Control.CURSOR_POINTING_HAND
	# the reason a claim is off is said in words, not only on the button
	claim_row.visible = claim.visible or recall.visible
	_refresh_feedback(claim_why if claim.visible and claim.disabled and _feedback.text == "" else "")


func _soft_people(view: Dictionary) -> Array:
	var out: Array = []
	for r in view.soft:
		var q = _person_by_id(String(r.id))
		if q != null:
			out.append(q)
	return out


## A button's look: the main choice's gold, or the plain one (a button that is off is plain: a dimmed gold does not read on the panel).
func _set_look(b: Button, primary: bool) -> void:
	if b.has_meta("look") and bool(b.get_meta("look")) == primary:
		return
	b.set_meta("look", primary)
	var look: Button = host._button(b.text, true) if primary else RadioKit.small_button(host, b.text, 38.0, 15)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, look.get_theme_stylebox(state))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(key, look.get_theme_color(key))
	look.free()


## The look of a switch's button: gold-edged while it is the one chosen.
func _style_segment(b: Button, on: bool) -> void:
	if b.has_meta("sk") and bool(b.get_meta("sk")) == on:
		return
	b.set_meta("sk", on)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st: StyleBox = host._button_style(state, false, false, false)
		st.content_margin_top = 0
		st.content_margin_bottom = 0
		st.content_margin_left = 6
		st.content_margin_right = 6
		if on and st is StyleBoxFlat:
			var flat: StyleBoxFlat = st
			flat.bg_color = Color(host.ACCENT, 0.2)
			flat.border_color = host.ACCENT
			flat.set_border_width_all(2)
		b.add_theme_stylebox_override(state, st)
	b.add_theme_color_override("font_color", host.ACCENT if on else host.INK)
	b.add_theme_color_override("font_hover_color", host.ACCENT if on else host.INK)
	b.add_theme_color_override("font_pressed_color", host.ACCENT if on else host.INK)


## Fills a box with one wrapped line for each of `lines` (made again only when they change).
func _set_lines(box: VBoxContainer, lines: Array, ink: Color) -> void:
	var sig := "|".join(lines)
	if box.has_meta("sig") and String(box.get_meta("sig")) == sig:
		return
	box.set_meta("sig", sig)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for line in lines:
		box.add_child(_para(String(line), 12, ink))
	box.visible = not lines.is_empty()


## The answer of the radio to the errand that was asked: who said what, and when they set off.
func _refresh_answer() -> void:
	if _answer.is_empty():
		answer_label.visible = false
		return
	var text := ""
	var ink: Color = host.INK
	if bool(_answer.ok):
		var going: Array = _answer.going
		var who := String(going[0].first) if not going.is_empty() else ""
		var line := String(_answer.line)
		text = ("%s: %s" % [who, line]) if who != "" and line != "" else line
		if not going.is_empty():
			text += "\n%s set%s off in about %d s." % [MapData.names(going), "s" if going.size() == 1 else "", maxi(1, int(ceilf(float(_answer.delay_s))))]
		ink = host.OK
	else:
		text = String(_answer.why)
		ink = host.WARN
	answer_label.text = text
	answer_label.add_theme_color_override("font_color", ink)
	answer_label.visible = text != ""


func _refresh_feedback(extra: String = "") -> void:
	var text := String(_feedback.text)
	var level := String(_feedback.level)
	if text == "" and extra != "":
		text = extra
		level = "warn"
	feedback_label.visible = text != ""
	if text == "":
		return
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", host.WARN if level == "warn" else (host.OK if level == "ok" else host.INK))


# ------------------------------------------------------------------- the foot --

## The parties that are out and the errands that wait for their delay, one line each.
func _refresh_foot() -> void:
	var s = _sim()
	var lines: Array = []
	for party_out in s.scavenge.parties:
		var people: Array = []
		for pid in party_out.members:
			var q = _person_by_id(String(pid))
			if q != null:
				people.append(q)
		var action := String(party_out.get("action", "loot"))
		var where := _place_name(String(party_out.site))
		var ride := String(party_out.get("vehicle", ""))
		var in_it := " in the %s" % _ride_name(ride) if ride != "" else ""
		var verb: String = {"loot": "looting", "scout": "scouting", "clear": "clearing"}.get(action, action)
		lines.append("%s, %s %s%s: %s." % [MapData.names(people), verb, where, in_it, MapData.due_text(s, party_out)])
	var radio = _radio()
	if radio != null and radio.get("errand_wait") != null:
		for e in radio.errand_wait:
			var people: Array = []
			for pid in e.get("ids", []):
				var q = _person_by_id(String(pid))
				if q != null:
					people.append(q)
			if people.is_empty():
				continue
			var verb: String = {"loot": "to loot", "scout": "to scout", "clear": "to clear"}.get(String(e.get("action", "loot")), "to go to")
			lines.append("%s, setting off %s %s in %d s." % [MapData.names(people), verb, _place_name(String(e.get("place", ""))), maxi(0, int(ceilf(float(e.get("left", 0.0)))))])
	if lines.is_empty():
		lines.append(FOOT_NOBODY)
	_set_lines(out_box, lines, host.INK)
	for c in out_box.get_children():
		if c is Label:
			c.add_theme_color_override("font_color", host.INK2 if lines == [FOOT_NOBODY] else host.INK)


# --------------------------------------------------------------------- the page --

## The full modal page of the same name (the Town Board, in a settlement game: the garrison and the whole card are there).
func full_page() -> void:
	if host != null and host.has_method("open_scavenge"):
		host.open_scavenge(null)


## The small tick on a chip that is ticked (the map's own, drawn in a corner).
class TickMark:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		anchor_left = 1.0
		anchor_right = 1.0
		offset_left = -19.0
		offset_right = -3.0
		offset_top = 3.0
		offset_bottom = 19.0

	func _draw() -> void:
		var Map = load("res://scripts/ui/town_map.gd")
		Map.draw_badge(self, "tick", size / 2.0, 7.0)
