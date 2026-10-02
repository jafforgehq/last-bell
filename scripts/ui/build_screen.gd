## The Build screen, a page of notebook paper over the game (key N, the hammer in the toolbar, or a click on a
## plot's sign in the yard). At the left the plots of the compound (seven: five in the yard and two on the wall) as a list of
## slips: the name, a tag for the kind of lot (yard or wall) and what is on it (Empty; the building going up with how far
## along it is; the building that stands). At the right the plot that is chosen:
##   - an empty one lists what its kind of lot allows, each with what it gives, its scrap and its builder-hours, and the
##     reason it cannot be ordered now (not enough scrap, the most there may be, a building it needs first) written
##     out under it, its Order button off with the same words as its tooltip; Order pays the scrap and puts a site up;
##   - a site shows how far along it is, who is building it and about how long it will take at the present pace
##     (the Builders' rates and the work left; "nobody is on the Builders job" with a button for the Jobs screen when
##     it is nobody), and Cancel, with the refund on the button (all of it before any work is done, else half);
##   - a building shows what it gives, and Demolish (half the scrap back): the first click arms the button, which
##     says so, and the second, within CONFIRM_S seconds, takes the building down.
## The foot says how much scrap is in the stores and how many people the compound has beds for (round 7's cap).
##
## In a settlement game (round 9: `sim.lots.on`) the page has more. The list begins with a slip for the **Lots page** (a card for
## each lot of the ring: its terms and Claim with the reason it cannot be pressed yet, and, once claimed, **one switch**, "Wall the
## streets as the scrap allows" (the lot's standing order), the street that is next and its price, how many of its walls stand and
## whether it is sealed; scripts/ui/build_lots.gd) and goes on with the yard's plots and, for each lot that is claimed, its ring
## plots (buildings stand on them as in the yard). A street's **mouth** (a wall across it) has no slip (round 11, the cut: twelve walls
## are one decision, not twelve): it is a pin on the **map** (scripts/ui/build_map.gd: the yard, or the whole block once a lot is
## claimed, a toggle chooses, with the plots as pins that the pointer and the keyboard can have), and the pin's card says what is
## there: the street open (with the one wall the standing order would put across it and a button to order it now, no list of kits),
## the wall going up, the wall that stands and how well it stands (walls are not demolished), the wall that is down (the Builders
## mend it by day while there is scrap). Nothing of this is there in the classic start.
##
## Hovering (or putting the keyboard on) a plot's slip marks the lot in the world: the HUD hands `{"plot": id}` to
## main.gd (`set_build_hover`, `hud.on_build_hover`), `{}` when the pointer leaves or the page closes, and main.gd
## says the page is up with `build_open`: the yard shows every plot's sign then (and otherwise only near the pointer: round 11).
##
## Everything is read from the buildings module (sim.build: plots, plot, catalogue, building, why_not, order, cancel,
## demolish, why_not_demolish, progress_of, active_site, rate, housing) and changed through it. The page follows the
## game while it is up (`refresh`, when the HUD is updated). Mouse and keyboard: every control can have the keyboard
## (Tab, Shift+Tab and the arrows go between them; Up and Down on the slips choose the plot, Right or Enter goes to
## the buttons of its detail, Left comes back; Enter on a street's pin on the map chooses it and goes to its card; Enter or Space presses a button; Esc, or N, closes the screen, Esc
## first putting away a Demolish that was armed). Opened by hud.open_build, which also pauses the rules while it is
## open and gives the speed back.
##
## It borrows the HUD's styles, colours and icons (the `hud` it is given) so it looks like the Jobs screen: the ink
## on the page is the HUD's PAPER_INK family (the chalk colours are for the boards).
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const BuildMap := preload("res://scripts/ui/build_map.gd")
const BuildLots := preload("res://scripts/ui/build_lots.gd")

## Emitted once, when the screen is gone.
signal closed

## The page is at most this wide, and keeps MARGIN from the window's edge.
const MAX_W := 960.0
const MARGIN := 12.0
## The room kept at the right of the words for the scroll bars.
const GUTTER := 14
## The list of plots is this wide at most (and at least LIST_MIN_W); the detail has the rest, COLUMN_GAP away.
const LIST_W := 238.0
const LIST_MIN_W := 196.0
const COLUMN_GAP := 14.0
## In a settlement game the list is a little wider (the streets' names are long).
const LIST_W_LOTS := 262.0
## A plot's slip: its height and the gap between two.
const ROW_H := 46.0
const ROW_GAP := 4
## The Order button's width, and the height of the buttons of the detail.
const ORDER_W := 92.0
const BUTTON_H := 34.0
## The veil over the game.
const DIM := 0.5
## The second click on Demolish must come within this many seconds (real time, not the rules' time).
const CONFIRM_S := 3.0
## The hours of the day the crew can build in: from half past six to the bell at seven, less the walk to the site and
## the meals. (The estimate of how long a site takes is the work left over the crew's rate, in these.)
const WORK_HOURS_A_DAY := 12.0
## The kinds of lot, as the tag on a plot's slip says them.
const KIND_TAGS := {"yard": "Yard", "wall": "Wall", "ring": "Street", "mouth": "Street wall"}
## The map is this share of the room the columns have, at most (the rest is for what is chosen).
const MAP_SHARE := 0.45
## The meter of a wall that stands well: a dark green (worn: the page's amber, failing: its red).
const WALL_OK := Color("#4f7330")
## The legend beside the map is this wide.
const LEGEND_W := 140.0
## The Lots page is chosen like a plot, by this id (it is in `rows` too).
const LOTS_PAGE := "@lots"
## The map card's legend: [colour, words].
const MAP_LEGEND := [[BuildMap.AMBER, "Open street"], [BuildMap.GOLD, "Wall going up"], [BuildMap.GREEN, "Wall stands"], [BuildMap.RED, "Wall down"], [BuildMap.RED, "Where the dead come in"]]

var hud
var sim
var build
var panel: PanelContainer
var list_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var list_box: VBoxContainer
var detail_box: VBoxContainer
var detail: PanelContainer
var close_button: Button
var error_label: Label
var hint_label: Label
var stock_label: Label
var housing_label: Label
## plot id -> {"plot", "row" (the slip, a Button), "name", "tag", "status", "meter"}
var rows := {}
## building id -> {"building", "card", "name", "cost", "blurb", "why", "order" (a Button)}
var entries := {}
## The plot that is chosen ("" never: there is always one).
var selected := ""
## The three things the detail can be: what can be built on an empty plot, a site going up, a building that stands.
var empty_view: VBoxContainer
var site_view: VBoxContainer
var built_view: VBoxContainer
var plot_title: Label
var plot_tag: Label
var plot_sub: Label
var site_title: Label
var site_meter: Meter
var site_percent: Label
var site_done: Label
var site_crew: Label
var site_note: Label
var site_gives: Label
var jobs_button: Button
var cancel_button: Button
var built_title: Label
var built_blurb: Label
var demolish_button: Button
var demolish_why: Label
## Demolish has been clicked once and waits for the second (for the seconds that are left).
var armed := false
var armed_left := 0.0
var _open := true
var _page: Control
var _dim: ColorRect
var _head: Control
var _foot: Control
var _sig := ""
var _marked := ""
var _marked_lot := ""
## The lots (a settlement game): whether the screen has them, the Lots slip, the page and its cards, the map and its two zoom
## buttons, the lots' captions in the list, and the parts of a mouth's detail.
var lots_on := false
var lots_row: Button = null
var lots_page = null
var lots_view: Control = null
var lot_cards := {}
var map: BuildMap = null
var map_card: PanelContainer = null
var map_yard_button: Button
var map_block_button: Button
var lot_headers := {}
var yard_header: Label = null
var mouth_info: Label
var empty_caption: Label
var built_caption: Label
var wall_box: VBoxContainer
var wall_meter: Meter
var wall_percent: Label
var wall_text: Label
## The player has chosen what the map shows (it no longer follows the claims).
var _map_chosen := false


## `h` is the HUD, `s` the game: the screen reads the buildings from `s.build`. `plot_id` is the plot to show first
## (the default is the one being built, else the first with nothing on it).
func setup(h, s, plot_id: String = "") -> void:
	hud = h
	sim = s
	build = sim.build
	lots_on = sim.get("lots") != null and sim.lots.on
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# a page over the whole window: the HUD knows it as a modal (the speech bubbles keep quiet under it)
	set_meta("modal", true)
	selected = plot_id if _can_choose(plot_id) else _default_plot()
	_build()
	refresh(true)
	resized.connect(_layout)
	# wrapped text only knows its height once it has a width: the rooms of the columns follow what is in them
	list_box.minimum_size_changed.connect(func(): _layout.call_deferred())
	detail_box.minimum_size_changed.connect(func(): _layout.call_deferred())
	_layout()
	_layout.call_deferred()
	_reveal_selected.call_deferred()
	set_process(false)


## The plot to show when none was asked for: the site being built, else the first lot with nothing on it.
func _default_plot() -> String:
	var active: Dictionary = build.active_site()
	if not active.is_empty():
		return String(active.id)
	# a lot that can be claimed and none claimed yet: the page of the lots, where it is
	if lots_on and sim.lots.claimed_on.is_empty():
		for l in sim.lots.lots():
			if String(sim.lots.why_not_claim(String(l.id))) == "":
				return LOTS_PAGE
	for pl in build.plots():
		if pl.building == "" and pl.site.is_empty() and String(pl.kind) != "mouth":
			return String(pl.id)
	return String(build.plots()[0].id) if not build.plots().is_empty() else ""


# ------------------------------------------------------------------- build --

func _build() -> void:
	# lighter than the dialogs' veil: the yard shows round the page, where the plots are marked
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
	head.add_child(hud._label("Build", Fonts.cond(700), 26, hud.PAPER_INK))
	var sub: Label = hud._caps("Order buildings and claim the streets; the Builders raise them by day" if lots_on else "Pick a plot and order a building; the Builders raise it by day", hud.PAPER_INK2)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	_head = head
	col.add_child(head)

	# the two columns: the plots, and the one that is chosen
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(COLUMN_GAP))
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_scroll = _scroll()
	list_box = _scroll_box(list_scroll)
	list_box.add_theme_constant_override("separation", ROW_GAP)
	list_box.add_child(hud._caps("Plots", hud.PAPER_INK2))
	if lots_on:
		_build_lots_list()
	else:
		for pl in build.plots():
			var slip := _build_row(pl)
			list_box.add_child(slip)
	cols.add_child(list_scroll)
	detail_scroll = _scroll()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box = _scroll_box(detail_scroll)
	_build_detail()
	cols.add_child(detail_scroll)
	col.add_child(cols)

	# the foot: the stores and the beds, what the keys are, Close
	var foot: VBoxContainer = hud._vbox(6)
	error_label = hud._label("", Fonts.sans(600), 13, hud.SLIP_MARK.danger)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.custom_minimum_size.x = 160
	error_label.visible = false
	foot.add_child(error_label)
	var row: HBoxContainer = hud._hbox(10)
	var facts: VBoxContainer = hud._vbox(2)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var counts := HFlowContainer.new()
	counts.add_theme_constant_override("h_separation", 16)
	counts.add_theme_constant_override("v_separation", 0)
	counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stock: HBoxContainer = hud._hbox(5)
	var scrap_icon: TextureRect = hud._icon("scrap", 16, hud.PAPER_INK2)
	scrap_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stock.add_child(scrap_icon)
	stock_label = hud._label("", Fonts.cond(700), 16, hud.PAPER_INK)
	stock.add_child(stock_label)
	counts.add_child(stock)
	housing_label = hud._label("", Fonts.cond(700), 16, hud.PAPER_INK)
	housing_label.tooltip_text = "The people the compound has beds for: the school's own and the bunk houses'"
	housing_label.mouse_filter = Control.MOUSE_FILTER_PASS
	counts.add_child(housing_label)
	facts.add_child(counts)
	hint_label = hud._label("Up and Down choose a plot, Enter goes to its buttons. N or Esc closes.", Fonts.sans(400), 13, hud.PAPER_INK2)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size.x = 120
	facts.add_child(hint_label)
	row.add_child(facts)
	close_button = _button("Close", true)
	close_button.tooltip_text = "Close the Build screen\nKey: N"
	close_button.pressed.connect(close)
	row.add_child(close_button)
	foot.add_child(row)
	_foot = foot
	col.add_child(foot)


## A column that scrolls by itself (the plots, the detail), with a gutter at the right for its scroll bar so that it
## never sits over the words: the box that holds what is in it.
func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(sc)
	return sc


func _scroll_box(sc: ScrollContainer) -> VBoxContainer:
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", GUTTER)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(gutter)
	var box: VBoxContainer = hud._vbox(8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(box)
	return box


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


func _rule(color: Color = Color(0, 0, 0, 0)) -> Control:
	var r := ColorRect.new()
	r.color = color if color.a > 0.0 else hud.PAPER_LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A wrapped line of the page: it asks for a little width so that it never folds into a column of letters.
func _para(size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = hud._label("", Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


## A card of the page: a sheet a little lighter than the paper with a thin ink edge (a gold wash and a heavy edge of
## dark gold while it is the one that is chosen).
func _card_style(chosen: bool = false) -> StyleBox:
	var s: StyleBoxFlat = hud._flat(Dialog.CARD_CHOSEN if chosen else Dialog.CARD, 4, Dialog.GOLD_EDGE if chosen else Color(hud.PAPER_INK, 0.3), false)
	s.set_border_width_all(2 if chosen else 1)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 9
	s.content_margin_bottom = 10
	return s


## A small tag in capitals (the kind of lot): ink on a faint wash of ink, a pill.
func _tag(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(hud.PAPER_INK, 0.08)
	s.border_color = Color(hud.PAPER_INK, 0.25)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", s)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l: Label = hud._caps(text, hud.PAPER_INK2)
	chip.add_child(l)
	chip.set_meta("label", l)
	return chip


# --------------------------------------------------------------------- plots --

## The list of a settlement game: the Lots slip, the compound's own plots, then, under a caption with its name, each lot's ring plots
## (the slips of a lot that is not claimed are there but not shown: a claim shows them). The streets' mouths have no slip: they are
## pins on the map.
func _build_lots_list() -> void:
	var lots_slip := _build_row({"id": LOTS_PAGE, "name": "Claim the streets", "kind": "lots"}, "Lots")
	lots_row = lots_slip
	list_box.add_child(lots_slip)
	yard_header = hud._caps("The compound", hud.PAPER_INK2)
	list_box.add_child(yard_header)
	for pl in build.plots():
		if String(pl.get("lot", "")) == "":
			list_box.add_child(_build_row(pl))
	for l in sim.lots.lots():
		var head: Label = hud._caps(String(l.name), hud.PAPER_INK2)
		head.visible = false
		lot_headers[String(l.id)] = head
		list_box.add_child(head)
		for id in l.get("plots", []):
			var pl: Dictionary = build.plot(String(id))
			if pl.is_empty():
				continue
			var slip := _build_row(pl)
			slip.visible = false
			list_box.add_child(slip)


## One plot's slip: a button with the name and the tag on one line and what is on the plot on the next (and, while
## a site goes up, a meter of how far along it is).
func _build_row(pl: Dictionary, tag_text: String = "") -> Button:
	var id := String(pl.id)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_FILL
	b.add_theme_stylebox_override("focus", Kit.focus_box(Dialog.GOLD_EDGE, 5))
	b.set_meta("plot", id)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 3)
	var inner: VBoxContainer = hud._vbox(0)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	var top: HBoxContainer = hud._hbox(6)
	var name_label: Label = hud._label(String(pl.name), Fonts.cond(700), 17, hud.PAPER_INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var street: bool = String(pl.kind) == "ring" or String(pl.kind) == "mouth"
	if street:
		# (the streets' names are long: a name that does not fit goes on to a second line, and the slip grows to hold it, see `_fit_rows`)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = 60
	else:
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_label)
	var tag := _tag(tag_text if tag_text != "" else String(KIND_TAGS.get(String(pl.kind), String(pl.kind).capitalize())))
	# (a slip of the streets has no room for a tag beside what is on it: its caption and its words say what it is)
	tag.visible = not street
	top.add_child(tag)
	inner.add_child(top)
	var bottom: HBoxContainer = hud._hbox(8)
	# (not clipped: a label that clips has no least width, and goes to nothing beside the meter)
	var status: Label = hud._label("", Fonts.sans(500), 13, hud.PAPER_INK3)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(status)
	var meter := Meter.new()
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.track = Color(hud.PAPER_INK, 0.2)
	meter.fill = hud.OAK
	meter.visible = false
	bottom.add_child(meter)
	inner.add_child(bottom)
	pad.add_child(inner)
	b.add_child(pad)
	b.pressed.connect(_on_row_pressed.bind(id))
	b.mouse_entered.connect(_on_row_hover.bind(id, true))
	b.mouse_exited.connect(_on_row_hover.bind(id, false))
	b.focus_entered.connect(_on_row_focus.bind(id))
	b.focus_exited.connect(_on_row_hover.bind(id, false))
	rows[id] = {"plot": pl, "row": b, "name": name_label, "tag": tag.get_meta("label"), "status": status, "meter": meter}
	_style_row(b, false)
	return b


## The look of a slip: a light card with a pencil edge; gold, with a heavy edge, while it is the plot that is chosen.
func _style_row(b: Button, chosen: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Dialog.CARD_CHOSEN if chosen else Dialog.CARD
		s.border_color = Dialog.GOLD_EDGE if chosen else Color(hud.PAPER_INK, 0.3)
		if state == "hover" and not chosen:
			s.bg_color = Dialog.CARD_CHOSEN.lerp(Dialog.CARD, 0.5)
			s.border_color = Dialog.GOLD_EDGE
		elif state == "pressed":
			s.bg_color = Dialog.CARD_CHOSEN.darkened(0.06)
		s.set_border_width_all(2 if chosen else 1)
		s.set_corner_radius_all(5)
		s.anti_aliasing = true
		b.add_theme_stylebox_override(state, s)


## A plot's slip was pressed: it is the one that is chosen. (A click puts the keyboard on the slip first, which has
## chosen it already: the click is for the press.)
func _on_row_pressed(id: String) -> void:
	hud.ui_sound("ui_click")
	select_plot(id)


## The keyboard came to a slip: the plot is chosen, and marked in the world.
func _on_row_focus(id: String) -> void:
	select_plot(id)
	_on_row_hover(id, true)


## The pointer or the keyboard is on a slip (or has left it): the lot is marked in the world.
func _on_row_hover(id: String, on: bool) -> void:
	if on:
		show_mark(id)
	elif _marked == id:
		show_mark("")


## The lot of this plot is marked in the world (the yard draws it); "" marks nothing. A page that is closed marks
## nothing: the controls it frees still send a last word as they go.
func show_mark(plot_id: String) -> void:
	if not _open:
		return
	if plot_id == LOTS_PAGE:
		plot_id = ""
	if plot_id == _marked and _marked_lot == "":
		return
	_marked = plot_id
	_marked_lot = ""
	if map != null:
		map.lit_lot = ""
		map.queue_redraw()
	hud.set_build_hover({"plot": plot_id} if plot_id != "" else {})


## A whole lot is marked in the world and on the map (the pointer or the keyboard is on its card); "" marks nothing.
func show_lot_mark(lot_id: String) -> void:
	if not _open:
		return
	if lot_id == _marked_lot and _marked == "":
		return
	_marked_lot = lot_id
	_marked = ""
	if map != null:
		map.lit_lot = lot_id
		map.queue_redraw()
	hud.set_build_hover({"lot": lot_id} if lot_id != "" else {})


## What is marked now ({"plot": id}, {"lot": id}, or {} for nothing).
func marks() -> Dictionary:
	if _marked_lot != "":
		return {"lot": _marked_lot}
	return {"plot": _marked} if _marked != "" else {}


## Whether this can be chosen: the Lots page (in a settlement game) or a plot that is open (the lots' plots only once they are claimed).
func _can_choose(id: String) -> bool:
	if id == LOTS_PAGE:
		return lots_on
	var pl: Dictionary = build.plot(id)
	return not pl.is_empty() and (not lots_on or sim.lots.plot_open(pl))


## Chooses a plot: its slip is gold, and the detail shows it. False if there is no such plot.
func select_plot(id: String) -> bool:
	if not _can_choose(id):
		return false
	var changed := id != selected
	if changed:
		if armed:
			_disarm()
		selected = id
		error_label.visible = false
	refresh(changed)
	if changed:
		_reveal_selected.call_deferred()
	return true


## The list scrolls to the chosen plot's slip, when the plot was chosen some other way than by its slip (a click on the
## plot's sign in the yard, a plot being built): the slip is in view.
func _reveal_selected() -> void:
	if _open and is_inside_tree() and rows.has(selected):
		list_scroll.ensure_control_visible(rows[selected].row)


# ------------------------------------------------------------------------- map --

## The map card (a settlement game): the yard or the whole block (a toggle says which), the plots as pins, and what the colours are.
func _build_map_card() -> Control:
	map_card = hud._panel(_card_style())
	map_card.mouse_filter = Control.MOUSE_FILTER_PASS
	map_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = hud._vbox(6)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 8)
	head.add_theme_constant_override("v_separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption: Label = hud._caps("The map", hud.PAPER_INK2)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(caption)
	var group := ButtonGroup.new()
	map_yard_button = _toggle("The yard", group)
	map_yard_button.pressed.connect(_on_map_zoom.bind(false))
	head.add_child(map_yard_button)
	map_block_button = _toggle("The whole block", group)
	map_block_button.pressed.connect(_on_map_zoom.bind(true))
	head.add_child(map_block_button)
	col.add_child(head)
	# the map, and at its right what its colours are
	var body: HBoxContainer = hud._hbox(10)
	map = BuildMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.setup(self, sim)
	map.picked.connect(_on_map_picked)
	map.pointed.connect(_on_map_pointed)
	body.add_child(map)
	var legend: VBoxContainer = hud._vbox(6)
	legend.custom_minimum_size.x = LEGEND_W
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for item in MAP_LEGEND:
		var entry: HBoxContainer = hud._hbox(5)
		var swatch := ColorRect.new()
		swatch.color = item[0]
		swatch.custom_minimum_size = Vector2(14, 6)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(swatch)
		entry.add_child(hud._label(String(item[1]), Fonts.sans(400), 12, hud.PAPER_INK2))
		legend.add_child(entry)
	body.add_child(legend)
	col.add_child(body)
	map_card.add_child(col)
	# the whole block as soon as there is something out in it, the yard before
	_set_map_whole(not sim.lots.claimed_on.is_empty())
	return map_card


## A button of the map's toggle: on while it is what the map shows.
func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := _button(text)
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(0, 30)
	# (on, it is the gold of a main choice: the one that the map shows)
	for state in ["pressed", "hover_pressed"]:
		var on: StyleBox = hud._button_style("hover" if state == "hover_pressed" else "normal", true, false, true)
		on.content_margin_top = 0
		on.content_margin_bottom = 0
		on.content_margin_left = 16
		on.content_margin_right = 16
		b.add_theme_stylebox_override(state, on)
	for color in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(color, hud.ACCENT_INK)
	return b


func _set_map_whole(on: bool) -> void:
	map.set_whole(on)
	map_block_button.set_pressed_no_signal(on)
	map_yard_button.set_pressed_no_signal(not on)


## One of the two buttons: the player has chosen what the map shows.
func _on_map_zoom(on: bool) -> void:
	_map_chosen = true
	hud.ui_sound("ui_click")
	_set_map_whole(on)


## A pin was pressed: the plot is chosen.
func _on_map_picked(id: String) -> void:
	hud.ui_sound("ui_click")
	select_plot(id)


## The pointer or the keyboard came to a pin (or left it): the plot is marked in the world.
func _on_map_pointed(id: String) -> void:
	show_mark(id)


# ---------------------------------------------------------------------- detail --

## The card of the detail: its heading (the plot and its tag), then the one of the three views that fits what is on
## the plot. Each is made once and shown or hidden as the plot changes.
func _build_detail() -> void:
	detail = hud._panel(_card_style())
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = hud._vbox(8)
	var head: HBoxContainer = hud._hbox(10)
	plot_title = hud._label("", Fonts.cond(700), 22, hud.PAPER_INK)
	plot_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# (a street's name is long: it goes on to a second line rather than push the page wider than the window)
	plot_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plot_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot_title.custom_minimum_size.x = 120
	head.add_child(plot_title)
	var tag := _tag("")
	plot_tag = tag.get_meta("label")
	head.add_child(tag)
	col.add_child(head)
	plot_sub = _para(13, hud.PAPER_INK2)
	col.add_child(plot_sub)
	if lots_on:
		mouth_info = _para(13, hud.PAPER_INK)
		mouth_info.visible = false
		col.add_child(mouth_info)
	col.add_child(_rule())
	col.add_child(_build_empty_view())
	col.add_child(_build_site_view())
	col.add_child(_build_built_view())
	if lots_on:
		lots_page = BuildLots.new()
		lots_page.setup(self)
		lots_view = lots_page.root
		lot_cards = lots_page.cards
		col.add_child(lots_view)
	detail.add_child(col)
	if lots_on:
		detail_box.add_child(_build_map_card())
	detail_box.add_child(detail)


## What can be built here: a slip for each building of the catalogue (the ones of the plot's kind are shown).
func _build_empty_view() -> Control:
	empty_view = hud._vbox(6)
	empty_caption = hud._caps("What can be built here", hud.PAPER_INK2)
	empty_view.add_child(empty_caption)
	for b in build.catalogue():
		empty_view.add_child(_build_entry(b))
	return empty_view


## One building of the catalogue: its name and what it costs, what it gives, why it cannot be ordered now, and Order.
func _build_entry(b: Dictionary) -> Control:
	var id := String(b.id)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = hud.PAPER_LINE
	s.border_width_bottom = 1
	s.content_margin_top = 4
	s.content_margin_bottom = 8
	s.content_margin_left = 0
	s.content_margin_right = 0
	card.add_theme_stylebox_override("panel", s)
	var row: HBoxContainer = hud._hbox(10)
	var left: VBoxContainer = hud._vbox(2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = hud._label(String(b.name), Fonts.cond(700), 19, hud.PAPER_INK)
	left.add_child(name_label)
	var cost := HFlowContainer.new()
	cost.add_theme_constant_override("h_separation", 12)
	cost.add_theme_constant_override("v_separation", 0)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrap: HBoxContainer = hud._hbox(4)
	var scrap_icon: TextureRect = hud._icon("scrap", 14, hud.PAPER_INK2)
	scrap_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scrap.add_child(scrap_icon)
	var scrap_label: Label = hud._label("%s scrap" % _num(float(b.scrap)), Fonts.cond(700), 14, hud.PAPER_INK)
	scrap.add_child(scrap_label)
	scrap.tooltip_text = "Paid when it is ordered"
	scrap.mouse_filter = Control.MOUSE_FILTER_PASS
	cost.add_child(scrap)
	var work: HBoxContainer = hud._hbox(4)
	var work_icon: TextureRect = hud._icon("build", 14, hud.PAPER_INK2)
	work_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	work.add_child(work_icon)
	var work_label: Label = hud._label("%s builder-hours" % _num(float(b.work)), Fonts.cond(700), 14, hud.PAPER_INK)
	work.add_child(work_label)
	work.tooltip_text = "Hours of work for the Builders at the base rate: a good builder does more than one an hour"
	work.mouse_filter = Control.MOUSE_FILTER_PASS
	cost.add_child(work)
	if b.has("wall_kit"):
		# a wall across a street: how much it takes before it falls
		var health: HBoxContainer = hud._hbox(4)
		var health_icon: TextureRect = hud._icon("wall", 14, hud.PAPER_INK2)
		health_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		health.add_child(health_icon)
		health.add_child(hud._label("%s health" % _num(float(b.hp)), Fonts.cond(700), 14, hud.PAPER_INK))
		health.tooltip_text = "How much damage the wall takes before it falls and opens the street"
		health.mouse_filter = Control.MOUSE_FILTER_PASS
		cost.add_child(health)
	left.add_child(cost)
	var blurb := _para(13, hud.PAPER_INK2)
	blurb.text = String(b.get("blurb", ""))
	left.add_child(blurb)
	var why := _para(13, hud.SLIP_MARK.warn, 600)
	why.visible = false
	left.add_child(why)
	row.add_child(left)
	var order_button := _button("Order", true)
	order_button.custom_minimum_size = Vector2(ORDER_W, BUTTON_H)
	order_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	order_button.pressed.connect(order.bind(id))
	row.add_child(order_button)
	card.add_child(row)
	entries[id] = {"building": b, "card": card, "name": name_label, "cost": cost, "blurb": blurb, "why": why, "order": order_button}
	return card


## A site going up: how far along, who builds it and for how long yet, what it will give; Cancel.
func _build_site_view() -> Control:
	site_view = hud._vbox(8)
	site_title = hud._label("", Fonts.cond(700), 20, hud.PAPER_INK)
	site_view.add_child(site_title)
	var bar: HBoxContainer = hud._hbox(10)
	site_meter = Meter.new()
	site_meter.custom_minimum_size = Vector2(60, 14)
	site_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	site_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	site_meter.track = Color(hud.PAPER_INK, 0.2)
	site_meter.fill = hud.OAK
	bar.add_child(site_meter)
	site_percent = hud._label("0%", Fonts.cond(700), 20, hud.PAPER_INK)
	site_percent.custom_minimum_size.x = 48
	site_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(site_percent)
	site_view.add_child(bar)
	site_done = _para(13, hud.PAPER_INK2)
	site_view.add_child(site_done)
	site_crew = _para(14, hud.PAPER_INK, 600)
	site_view.add_child(site_crew)
	jobs_button = _button("Open the Jobs screen")
	jobs_button.tooltip_text = "Put someone on the Builders job on the Jobs screen\nKey: J"
	jobs_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	jobs_button.custom_minimum_size = Vector2(0, BUTTON_H)
	jobs_button.pressed.connect(open_jobs)
	site_view.add_child(jobs_button)
	site_note = _para(13, hud.PAPER_INK3)
	site_view.add_child(site_note)
	site_view.add_child(hud._caps("What it will give", hud.PAPER_INK2))
	site_gives = _para(14, hud.PAPER_INK)
	site_view.add_child(site_gives)
	cancel_button = _button("Cancel the order")
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel_button.custom_minimum_size = Vector2(0, BUTTON_H)
	cancel_button.pressed.connect(cancel)
	site_view.add_child(cancel_button)
	return site_view


## A building that stands: what it gives; Demolish.
func _build_built_view() -> Control:
	built_view = hud._vbox(8)
	built_title = hud._label("", Fonts.cond(700), 20, hud.PAPER_INK)
	built_view.add_child(built_title)
	built_caption = hud._caps("What it gives", hud.PAPER_INK2)
	built_view.add_child(built_caption)
	built_blurb = _para(14, hud.PAPER_INK)
	built_view.add_child(built_blurb)
	if lots_on:
		# a wall across a street: how well it stands
		wall_box = hud._vbox(6)
		var bar: HBoxContainer = hud._hbox(10)
		wall_meter = Meter.new()
		wall_meter.custom_minimum_size = Vector2(60, 14)
		wall_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wall_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wall_meter.track = Color(hud.PAPER_INK, 0.2)
		wall_meter.fill = hud.OAK
		bar.add_child(wall_meter)
		wall_percent = hud._label("100%", Fonts.cond(700), 20, hud.PAPER_INK)
		wall_percent.custom_minimum_size.x = 56
		wall_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bar.add_child(wall_percent)
		wall_box.add_child(bar)
		wall_text = _para(14, hud.PAPER_INK, 600)
		wall_box.add_child(wall_text)
		built_view.add_child(wall_box)
	demolish_button = _button("Demolish")
	demolish_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	demolish_button.custom_minimum_size = Vector2(0, BUTTON_H)
	demolish_button.pressed.connect(demolish)
	built_view.add_child(demolish_button)
	demolish_why = _para(13, hud.SLIP_MARK.warn, 600)
	demolish_why.visible = false
	built_view.add_child(demolish_why)
	return built_view


## A meter of how far along something is: a pencil-line track, an oak fill.
class Meter:
	extends Control
	var value := 0.0
	var track := Color(0, 0, 0, 0.2)
	var fill := Color("#8a6238")

	func _init() -> void:
		custom_minimum_size = Vector2(36, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		_pill(Rect2(Vector2.ZERO, size), track)
		if value > 0.0:
			_pill(Rect2(0, 0, maxf(size.y, size.x * clampf(value, 0.0, 1.0)), size.y), fill)

	func _pill(rect: Rect2, c: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(size.y / 2.0))
		sb.anti_aliasing = true
		draw_style_box(sb, rect)


# ----------------------------------------------------------------------- layout --

## A slip whose name does not fit on a line has two (or more): it is made as tall as they need, for a column `col_w` wide.
func _fit_rows(col_w: float) -> void:
	var avail := col_w - float(GUTTER) - 20.0 - 2.0
	for id in rows:
		var r: Dictionary = rows[id]
		var label: Label = r.name
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			continue
		var font: Font = label.get_theme_font("font")
		var px: int = label.get_theme_font_size("font_size")
		var one := font.get_string_size("Ag", HORIZONTAL_ALIGNMENT_LEFT, -1, px).y
		var lines := maxi(1, roundi(font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, avail, px, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y / one))
		var want := ROW_H + float(lines - 1) * (one + 1.0)
		if absf(r.row.custom_minimum_size.y - want) > 0.5:
			r.row.custom_minimum_size.y = want


func _layout() -> void:
	if panel == null or not is_inside_tree():
		return
	var pw := minf(size.x - 2.0 * MARGIN, MAX_W)
	panel.custom_minimum_size.x = maxf(pw, 0.0)
	var frame: StyleBox = panel.get_theme_stylebox("panel")
	var inner := pw - frame.get_margin(SIDE_LEFT) - frame.get_margin(SIDE_RIGHT)
	# the plots take what they need up to LIST_W; the detail has the rest
	if lots_on:
		list_scroll.custom_minimum_size.x = clampf((inner - COLUMN_GAP) * 0.4, LIST_MIN_W, LIST_W_LOTS)
		_fit_rows(list_scroll.custom_minimum_size.x)
	else:
		list_scroll.custom_minimum_size.x = clampf((inner - COLUMN_GAP) * 0.38, LIST_MIN_W, LIST_W)
	# the columns scroll when the window is too short for them
	var chrome: float = _head.get_combined_minimum_size().y + _foot.get_combined_minimum_size().y + 16.0 + frame.get_minimum_size().y + 12.0
	var room := maxf(140.0, size.y - 2.0 * MARGIN - chrome)
	if map != null:
		# the map takes a share of what the columns have, and leaves the rest for what is chosen
		map.max_h = clampf(room * MAP_SHARE, BuildMap.MIN_H, BuildMap.MAX_H)
		map.refresh()
	var want := maxf(list_box.get_combined_minimum_size().y, detail_box.get_combined_minimum_size().y)
	var h := minf(want, room)
	list_scroll.custom_minimum_size.y = h
	detail_scroll.custom_minimum_size.y = h


# ----------------------------------------------------------------------- refresh --

## What the page shows, in one line: it is redrawn only when it changes.
func _signature() -> String:
	var sig := "%s|%d|%d|%d|%s|%s|%s|%s;" % [selected, build.version, roundi(float(sim.stock.scrap) * 10.0), build.housing(), armed, _crew_signature(), String(sim.phase), sim.bell_rung]
	for pl in build.plots():
		sig += "%s:%s:%s:%d;" % [pl.id, pl.building, String(pl.site.get("building", "")), roundi(build.progress_of(String(pl.id)) * 1000.0)]
	if lots_on:
		sig += _lots_signature()
	return sig


## What the lots add to what the page shows: the claims and what they hang on, the streets that are open, how each wall stands.
func _lots_signature() -> String:
	var sig := "L%d|%d|%d|%d;" % [sim.lots.claimed_on.size(), sim.day, int(sim.town.cleared_count()), sim.lots.open_streets()]
	for l in sim.lots.lots():
		sig += "%s%s:%s;" % ["A" if sim.lots.auto_walling(String(l.id)) else "a", String(l.id), sim.lots.next_street(String(l.id))]
	for m in sim.lots.mouths():
		var seg = sim.lots.segment_at(String(m.id))
		if seg != null:
			sig += "%s:%d:%d;" % [m.id, roundi(float(seg.hp)), int(seg.state)]
	return sig


## The Builders as the estimate sees them: who is on the job, whether they can work, and how fast.
func _crew_signature() -> String:
	var sig := String(build.active_site().get("id", ""))
	for p in sim.jobs.crew_of("builders"):
		sig += "|%s,%s,%s,%d" % [p.id, p.away != null, p.downed, roundi(float(build.rate(p)) * 100.0)]
	return sig


## Brings the page in line with the game: the foot, every slip, the detail.
func refresh(force: bool = false) -> void:
	if not _open:
		return
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	_refresh_foot()
	if lots_on:
		_refresh_lots()
	for pl in build.plots():
		if rows.has(String(pl.id)):
			_refresh_row(pl)
	_refresh_detail()
	if lots_on:
		_refresh_map()


## The lots' part of the list: the slips and captions of the lots that are claimed, the Lots slip's words, the page.
func _refresh_lots() -> void:
	for l in sim.lots.lots():
		var id := String(l.id)
		var open: bool = sim.lots.claimed(id)
		if lot_headers.has(id):
			lot_headers[id].visible = open
		for pid in l.get("plots", []):
			if rows.has(String(pid)):
				rows[String(pid)].row.visible = open
	var r: Dictionary = rows[LOTS_PAGE]
	var total: int = sim.lots.lots().size()
	var have: int = sim.lots.claimed_on.size()
	_set_text(r.status, "%d of %d claimed" % [have, total], hud.PAPER_INK if have > 0 else hud.PAPER_INK3)
	var chosen := selected == LOTS_PAGE
	if bool(r.row.get_meta("chosen", false)) != chosen:
		r.row.set_meta("chosen", chosen)
		_style_row(r.row, chosen)
	r.row.tooltip_text = "The streets round the school: %d of %d lots claimed" % [have, total]
	lots_page.refresh()


## The map follows the game: what is chosen, the pins, and (until the player chooses) the whole block once a lot is claimed.
func _refresh_map() -> void:
	var pl: Dictionary = build.plot(selected)
	map.selected = selected if selected != LOTS_PAGE else ""
	if not _map_chosen:
		_set_map_whole(not sim.lots.claimed_on.is_empty())
	# a plot out in the streets is not on the map of the yard: the map shows the block
	if not pl.is_empty() and String(pl.get("lot", "")) != "" and not map.whole:
		_set_map_whole(true)
	map.refresh()


func _refresh_foot() -> void:
	stock_label.text = "Scrap in the stores: %d" % int(float(sim.stock.scrap))
	var n: int = build.housing()
	housing_label.text = "Beds for %d %s" % [n, "person" if n == 1 else "people"]


func _refresh_row(pl: Dictionary) -> void:
	var id := String(pl.id)
	var r: Dictionary = rows[id]
	var status := ""
	var ink: Color = hud.PAPER_INK3
	var meter: Meter = r.meter
	meter.visible = false
	var mouth: bool = String(pl.kind) == "mouth"
	if pl.building != "":
		status = String(build.building(String(pl.building)).name)
		if mouth:
			var seg = sim.lots.segment_at(id)
			if seg != null:
				status += ": down" if int(seg.state) == 3 else ": %d%%" % roundi(float(seg.hp) / maxf(1.0, float(seg.max_hp)) * 100.0)
		ink = hud.PAPER_INK
	elif not pl.site.is_empty():
		var share: float = build.progress_of(id)
		status = "%s: %d%%" % [String(build.building(String(pl.site.building)).name), mini(99, floori(share * 100.0))]
		ink = hud.PAPER_INK
		meter.visible = true
		meter.value = share
		meter.queue_redraw()
	else:
		status = "Open street" if mouth else "Empty"
	_set_text(r.status, status, ink)
	var chosen := id == selected
	if bool(r.row.get_meta("chosen", false)) != chosen:
		r.row.set_meta("chosen", chosen)
		_style_row(r.row, chosen)
	r.row.tooltip_text = "%s: %s" % [String(pl.name), status.to_lower() if status == "Empty" or status == "Open street" else status]


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


## The detail for the plot that is chosen.
func _refresh_detail() -> void:
	# (the Lots page is the cards first, and the map under them; a plot has the map over it)
	if map_card != null:
		var at := 1 if selected == LOTS_PAGE else 0
		if map_card.get_index() != at:
			detail_box.move_child(map_card, at)
	if selected == LOTS_PAGE:
		_refresh_lots_detail()
		return
	var pl: Dictionary = build.plot(selected)
	if pl.is_empty():
		return
	var kind := String(pl.kind)
	if lots_on:
		lots_view.visible = false
		mouth_info.visible = kind == "mouth"
	plot_title.text = String(pl.name)
	plot_tag.text = String(KIND_TAGS.get(kind, kind.capitalize())).to_upper()
	if kind == "mouth":
		plot_sub.text = "A wall across a street, %s tiles wide" % _num(maxf(float(pl.size.x), float(pl.size.y)))
		mouth_info.text = _mouth_text(pl)
	else:
		plot_sub.text = "%s lot, %s by %s tiles" % [String(KIND_TAGS.get(kind, kind.capitalize())), _num(float(pl.size.x)), _num(float(pl.size.y))]
	var standing := String(pl.building) != ""
	var going_up: bool = not pl.site.is_empty()
	empty_view.visible = not standing and not going_up
	site_view.visible = going_up
	built_view.visible = standing
	if standing:
		_refresh_built(pl)
	elif going_up:
		_refresh_site(pl)
	else:
		_refresh_empty(pl)


## The Lots page chosen: the heading, and nothing of a plot's three views.
func _refresh_lots_detail() -> void:
	plot_title.text = "The streets round the school"
	plot_tag.text = "LOTS"
	plot_sub.text = "Claim a lot to build in its streets, then switch on its standing order: the Builders wall its streets one after another as the scrap allows"
	mouth_info.visible = false
	empty_view.visible = false
	site_view.visible = false
	built_view.visible = false
	lots_view.visible = true


## What a mouth is, in words: which street, where the dead of it come from, what else shuts it, what it belongs to.
func _mouth_text(pl: Dictionary) -> String:
	var m: Dictionary = sim.lots.mouth(String(pl.id))
	var street := int(m.get("spawn", 0)) + 1
	var side: String = {"N": "north", "S": "south", "E": "east", "W": "west"}.get(String(m.get("side", "")), "edge of the map")
	var text := "Street %d of %d: the dead who come in from the %s reach the ring here." % [street, sim.lots.streets(), side]
	var others: Array = []
	for o in sim.lots.mouths():
		if int(o.get("spawn", -1)) == int(m.get("spawn", -2)) and String(o.id) != String(m.id):
			others.append(String(o.name))
	if not others.is_empty():
		text += " The street is shut only when this wall and %s stand." % ", ".join(others)
	var lot: Dictionary = sim.lots.lot(String(m.get("lot", "")))
	if not lot.is_empty():
		text += " Part of %s: %d of %d walls stand." % [String(lot.name).to_lower(), sim.lots.standing_walls(String(lot.id)), sim.lots.mouths_of(String(lot.id)).size()]
		if String(pl.building) == "" and pl.site.is_empty():
			text += " Its standing order is %s." % ("on: this street is walled in its turn" if sim.lots.auto_walling(String(lot.id)) else "off (the switch is on the Lots page)")
	return text


func _refresh_empty(pl: Dictionary) -> void:
	var mouth: bool = String(pl.kind) == "mouth"
	# (a street has no list of kits: the one wall the standing order would put across it, to order now)
	var best: String = String(sim.lots.best_kit(String(pl.id))) if mouth and lots_on else ""
	if lots_on:
		empty_caption.text = "The street is open: wall it now" if mouth else "What can be built here"
	for b in build.catalogue():
		var id := String(b.id)
		var e: Dictionary = entries[id]
		var allowed: bool
		if b.has("wall_kit"):
			allowed = mouth and id == best
		else:
			# (a ring plot takes what is for the yard, and what is only for the streets: `ring`)
			allowed = b.plots.has(String(pl.kind)) or (String(pl.kind) == "ring" and b.plots.has("yard"))
		e.card.visible = allowed
		if not allowed:
			continue
		var why := String(build.why_not(String(pl.id), id))
		var order_button: Button = e.order
		order_button.disabled = why != ""
		order_button.focus_mode = Control.FOCUS_NONE if why != "" else Control.FOCUS_ALL
		order_button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if why != "" else Control.CURSOR_POINTING_HAND
		order_button.tooltip_text = _sentence(why) if why != "" else "Order the %s: %s scrap now, then the Builders raise it" % [String(b.name).to_lower(), _num(float(b.scrap))]
		var why_label: Label = e.why
		why_label.text = _sentence(why)
		why_label.visible = why != ""


func _refresh_site(pl: Dictionary) -> void:
	var id := String(pl.id)
	var b: Dictionary = build.building(String(pl.site.building))
	var share: float = build.progress_of(id)
	# (a name may be a plural: Floodlights, Greenhouse beds)
	site_title.text = "%s: going up" % String(b.name)
	site_meter.value = share
	site_meter.queue_redraw()
	site_percent.text = "%d%%" % mini(99, floori(share * 100.0))
	var work := float(pl.site.work)
	var done := minf(float(pl.site.progress), work)
	site_done.text = "%s of %s builder-hours done." % [_num(done, 1), _num(work)]
	var first := _crew_line(pl)
	site_crew.text = first.text
	jobs_button.visible = first.no_crew
	site_note.text = _night_note()
	site_gives.text = String(b.get("blurb", ""))
	# the refund is on the button: all of it before any work is done, else half
	var back := _refund_of_site(pl)
	cancel_button.text = "Cancel the order (+%s scrap)" % _num(back)
	cancel_button.tooltip_text = ("No work has been done: all the scrap comes back" if float(pl.site.progress) <= 0.0 else "Work has begun: half the scrap comes back") + "\nThe plot is free again"


## What Cancel gives back (the same sum the buildings module works out).
func _refund_of_site(pl: Dictionary) -> float:
	var share := 1.0 if float(pl.site.progress) <= 0.0 else float(build.REFUND_SHARE)
	return float(pl.site.scrap) * share


func _refresh_built(pl: Dictionary) -> void:
	var b: Dictionary = build.building(String(pl.building))
	built_title.text = String(b.name)
	built_blurb.text = String(b.get("blurb", ""))
	var back := float(b.scrap) * float(build.REFUND_SHARE)
	var why := String(build.why_not_demolish(String(pl.id)))
	if lots_on:
		var wall: bool = String(pl.kind) == "mouth"
		wall_box.visible = wall
		built_caption.text = "How it stands" if wall else "What it gives"
		demolish_button.visible = not wall
		if wall:
			_refresh_wall(pl)
			demolish_why.text = _sentence(why)
			demolish_why.visible = why != ""
			return
	demolish_button.disabled = why != ""
	demolish_button.focus_mode = Control.FOCUS_NONE if why != "" else Control.FOCUS_ALL
	demolish_button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if why != "" else Control.CURSOR_POINTING_HAND
	if armed and why == "":
		demolish_button.text = "Click again to demolish (+%s scrap)" % _num(back)
		demolish_button.tooltip_text = "Click again within %d seconds, or leave it: nothing is taken down until then" % int(CONFIRM_S)
	else:
		demolish_button.text = "Demolish (+%s scrap)" % _num(back)
		demolish_button.tooltip_text = _sentence(why) if why != "" else "Take the %s down: half of its scrap comes back, its effects end and the plot is free\nTwo clicks: the second within %d seconds" % [String(b.name).to_lower(), int(CONFIRM_S)]
	demolish_why.text = _sentence(why)
	demolish_why.visible = why != ""


## A wall across a street: its health as a meter and a percentage, and in words what that means for the street.
func _refresh_wall(pl: Dictionary) -> void:
	var seg = sim.lots.segment_at(String(pl.id))
	if seg == null:
		wall_text.text = "No wall stands here."
		wall_meter.value = 0.0
		wall_percent.text = "0%"
		wall_meter.queue_redraw()
		return
	var f := clampf(float(seg.hp) / maxf(1.0, float(seg.max_hp)), 0.0, 1.0)
	wall_meter.value = f
	wall_meter.fill = hud.SLIP_MARK.danger if f < 0.34 else (hud.SLIP_MARK.warn if f < 0.67 else WALL_OK)
	wall_meter.queue_redraw()
	wall_percent.text = "%d%%" % roundi(f * 100.0)
	var words := ""
	match int(seg.state):
		0:
			words = "Standing: it holds the street."
		1:
			words = "Worn: it has taken a beating and still holds the street."
		2:
			words = "Failing: one more bad night may break it."
		_:
			words = "Down: the street is open. The Builders mend it by day while there is scrap."
	wall_text.text = "%d of %d health. %s" % [roundi(float(seg.hp)), roundi(float(seg.max_hp)), words]


## The line about who is building the site: [text, whether nobody is on the job]. For the site the crew works on now,
## their names and about how long it will take at the present pace; for one that waits its turn, which comes first.
func _crew_line(pl: Dictionary) -> Dictionary:
	var crew: Array = sim.jobs.crew_of("builders")
	if crew.is_empty():
		return {"text": "Nobody is on the Builders job, so nothing will go up.", "no_crew": true}
	var able: Array = []
	for p in crew:
		if p.away == null and not p.downed and not sim.morale.breakdown(p):
			able.append(p)
	var active: Dictionary = build.active_site()
	if not active.is_empty() and String(active.id) != String(pl.id):
		return {"text": "Waiting its turn: the Builders are at the %s (%s) first." % [String(build.building(String(active.site.building)).name).to_lower(), String(active.name)], "no_crew": false}
	if able.is_empty():
		return {"text": "%s cannot build just now (away or hurt)." % _names(crew), "no_crew": false}
	var per_hour := 0.0
	for p in able:
		per_hour += float(build.rate(p))
	var left := maxf(0.0, float(pl.site.work) - float(pl.site.progress))
	return {"text": "%s: %s at the present pace." % [_names(able), _time_text(left / maxf(per_hour, 0.001))], "no_crew": false}


## What the crew's day is like: they build by day, and wear no hammers at night.
func _night_note() -> String:
	var phase := String(sim.phase)
	var night: bool = phase == "night" or phase == "dawn" or (phase == "dusk" and bool(sim.bell_rung))
	if night:
		return "It is night: the Builders hold the posts, and the site waits for the morning."
	return "The Builders work by day. A badly worn wall comes first."


## "Walt", "Walt and Hector", "Walt, Hector and Dez".
static func _names(people: Array) -> String:
	var names: Array = []
	for p in people:
		names.append(String(p.first))
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]


## How long `hours` of work take: "about 1.4 days", "about 6 hours" (a day is WORK_HOURS_A_DAY of them).
static func _time_text(hours: float) -> String:
	if hours < 1.0:
		return "less than an hour"
	if hours < WORK_HOURS_A_DAY - 0.5:
		var n := roundi(hours)
		return "about %d hour%s" % [n, "" if n == 1 else "s"]
	var days := snappedf(hours / WORK_HOURS_A_DAY, 0.1)
	return "about %s day%s" % [_num(days, 1), "" if is_equal_approx(days, 1.0) else "s"]


## A number for words: whole when it is, else up to `places` decimals ("14", "6.5").
static func _num(x: float, places: int = 1) -> String:
	if absf(x - roundf(x)) < 0.05:
		return str(roundi(x))
	return ("%." + str(places) + "f") % x


## "it needs 30 scrap" -> "It needs 30 scrap."
static func _sentence(text: String) -> String:
	if text == "":
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


# ---------------------------------------------------------------------- acting --

## Orders `building_id` on the chosen plot: the scrap is paid and a site goes up. False, and the page says why, if it
## cannot be ordered.
func order(building_id: String) -> bool:
	error_label.visible = false
	var why := String(build.why_not(selected, building_id))
	if why != "":
		_say(why)
		return false
	if not build.order(selected, building_id):
		_say("it cannot be ordered")
		return false
	hud.ui_sound("ui_confirm")
	refresh(true)
	_focus_row(selected)
	return true


## Claims a lot of the ring (the Claim button of its card): the scrap is paid, its plots and mouths open on the list and the map. False,
## and the page says why, if it cannot be claimed.
func claim_lot(id: String) -> bool:
	error_label.visible = false
	if not lots_on:
		return false
	var why := String(sim.lots.why_not_claim(id))
	if why != "":
		_say(why)
		return false
	if not sim.lots.claim(id):
		_say("it cannot be claimed")
		return false
	hud.ui_sound("ui_confirm")
	refresh(true)
	_focus_row(LOTS_PAGE)
	return true


## Cancels the site on the chosen plot: all the scrap back if no work was done, else half.
func cancel() -> bool:
	error_label.visible = false
	if not build.cancel(selected):
		_say("there is nothing to cancel")
		return false
	hud.ui_sound("ui_click")
	refresh(true)
	_focus_row(selected)
	return true


## Demolish, in two clicks: the first arms the button (it says so), the second, within CONFIRM_S seconds, takes the
## building down. True when it came down.
func demolish() -> bool:
	error_label.visible = false
	var why := String(build.why_not_demolish(selected))
	if why != "":
		_say(why)
		return false
	if not armed:
		armed = true
		armed_left = CONFIRM_S
		set_process(true)
		hud.ui_sound("ui_click")
		refresh(true)
		return false
	_disarm()
	if not build.demolish(selected):
		_say("it cannot be taken down")
		return false
	hud.ui_sound("ui_confirm")
	refresh(true)
	_focus_row(selected)
	return true


## The second click did not come: the button is as it was.
func _disarm() -> void:
	if not armed:
		return
	armed = false
	armed_left = 0.0
	set_process(false)
	if _open:
		refresh(true)


## Real time passes for the armed button (the rules wait while the page is up, so this is not their clock).
func _process(delta: float) -> void:
	if armed:
		armed_left -= delta
		if armed_left <= 0.0:
			_disarm()


## The Builders' site waits for nobody: the page gives way to the Jobs screen, where they are picked.
func open_jobs() -> void:
	hud.open_jobs_from_build()


func _say(text: String) -> void:
	error_label.text = _sentence(text)
	error_label.visible = true
	hud.ui_sound("ui_error")


# ----------------------------------------------------------------------- closing --

func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	if armed:
		armed = false
	_open = false
	set_process_input(false)
	set_process(false)
	hide()
	closed.emit()
	queue_free()


# ---------------------------------------------------------------------- keyboard --

## Whether `c` is one of the plots' slips.
func _is_row(c) -> bool:
	return c is Button and c.has_meta("plot")


## Whether `c` is one of the map's pins.
func _is_pin(c) -> bool:
	return c is Button and c.has_meta("pin")


## The keyboard goes on to the buttons of the card of the plot a pin has just chosen (when it is the one that is chosen).
func _enter_detail_of(id: String) -> void:
	if _open and is_inside_tree() and selected == id:
		_enter_detail()


## The slip of this plot has the keyboard.
func _focus_row(id: String) -> void:
	var b: Control = null
	if rows.has(id):
		b = rows[id].row
	elif map != null and map.pins.has(id):
		b = map.pins[id]    # (a street's wall has no slip: the keyboard goes to its pin on the map)
	if b != null and is_inside_tree() and b.is_visible_in_tree():
		b.grab_focus()


## The first control of the detail the keyboard can have: the first Order that is on, the Cancel, the Demolish.
func _detail_controls() -> Array:
	var out: Array = []
	if lots_on and selected == LOTS_PAGE:
		return lots_page.controls()
	if empty_view.visible:
		for b in build.catalogue():
			var e: Dictionary = entries[String(b.id)]
			if e.card.visible:
				out.append(e.order)
	if site_view.visible:
		out.append(jobs_button)
		out.append(cancel_button)
	if built_view.visible:
		out.append(demolish_button)
	return out


## The keyboard goes from the slips to the buttons of the detail (to the first that can have it).
func _enter_detail() -> bool:
	for c in _detail_controls():
		if c.is_visible_in_tree() and not c.disabled and c.focus_mode != Control.FOCUS_NONE:
			c.grab_focus()
			return true
	return false


## Whether the keyboard is in the detail (on one of its buttons).
func _in_detail(c) -> bool:
	return c is Control and detail.is_ancestor_of(c)


## The keyboard goes to the chosen plot's slip (the first Tab or arrow, with nothing focused).
func focus_default() -> void:
	if not _open or not is_inside_tree():
		return
	_focus_row(selected)


## While the page is up every key belongs to it: Esc puts away an armed Demolish and then closes the screen, N closes
## it, Tab, the arrows, Enter and Space go on to the controls (and Tab or an arrow with nothing focused puts the
## keyboard on the chosen plot), Right or Enter on a slip goes to the detail's buttons and Left comes back; every
## other key is not the game's.
func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed:
		return
	var code: Key = ev.keycode
	var plain: bool = not ev.ctrl_pressed and not ev.meta_pressed and not ev.alt_pressed
	if ev.echo and (code == KEY_ESCAPE or code == KEY_N):
		# a key that is held down shuts one thing, not the page and then what is under it
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if code == KEY_ESCAPE:
		if armed:
			_disarm()
		else:
			close()
	elif code == KEY_N and plain:
		close()
	elif code in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and focus == null:
		focus_default()
	elif (code == KEY_RIGHT or code == KEY_ENTER or code == KEY_KP_ENTER) and _is_row(focus) and plain and not ev.shift_pressed:
		_enter_detail()
	elif (code == KEY_ENTER or code == KEY_KP_ENTER) and _is_pin(focus) and plain and not ev.shift_pressed:
		# (the pin's own press chooses the street; the keyboard then goes on to the street's card, as it does from a slip)
		_enter_detail_of.call_deferred(String(focus.get_meta("pin")))
		return
	elif code == KEY_LEFT and _in_detail(focus) and plain:
		_focus_row(selected)
	elif code in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
