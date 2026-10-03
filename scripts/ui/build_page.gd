extends VBoxContainer
## The Build page of the radio panel (round 18): the Build screen's list of buildings, small enough to sit beside the yard, and not
## modal (the game does not pause; nothing here takes a key, so WASD and E keep working). The modal screen (build_screen.gd) stays as
## the full page, and in a settlement game it is also the way to the lots, the street map and the walls (this page does not re-implement
## them).
##
## A SLIP for each building the compound can have, one for each of its homes (a building that may stand twice, the bunk house, the tents,
## the watchtower, the scrap yard, has "1 of 2" and "2 of 2"; the second is ordered after the first): the building's name and one line of
## what it is now. That line is its cost ("30 scrap, 24 builder-hours"), or, in amber, the reason it cannot be ordered now ("It needs 30
## scrap", "It needs the workshop first", "Order the first bunk house first": the words are the simulation's, `radio.build_willingness`
## and `build.why_not`; the page never makes up a reason), or the site and how far along it is ("Going up: 45%", with a meter), or "Built".
## A slip that is pressed opens under itself (pressed again, it closes): what the building gives, where it goes (the home's name and why),
## then by what the building is now
##   - not built: what it costs, the crew note (advisory, in blue-grey: who builds it; with nobody on the Builders job a button takes
##     the player to the Jobs page, `host.open_radio("jobs", {"focus": "builders"})`) and **Order** (`radio.request_build`: the answer
##     is the lead builder's words, green, six seconds; a refusal shows amber). The button is off, with the reason as its tooltip, while
##     the building cannot be ordered;
##   - a site: how far along, who builds it and for how long yet, **Cancel** with the refund on the button (all of the scrap before any
##     work is done, else half: `build.cancel`);
##   - a building: **Demolish** (half the scrap back; the first press arms it and says so, the second, within CONFIRM_S seconds of real
##     time, takes it down: `build.demolish`; off, with the reason, while another building needs it).
## Hovering or choosing a slip marks its home in the yard (`host.set_build_hover({"plot": id})`, the chosen one's again when the pointer
## leaves, `{}` while the page is not shown). The foot says how much scrap the stores hold and how many people the compound has beds for,
## and has **Full page** (`host.open_build()`: the modal screen) and, in a settlement game only, **Streets and map...** (the same
## screen on its Lots page).
##
## The page is one of the radio panel's pages: `setup(host, sim_getter, options)`, `refresh()` (each HUD update while it is shown; only
## what changed is redrawn), `focus_on(id)` (a building's id or a home's), `full_page()`. Every control is FOCUS_NONE (the panel never
## steals the keyboard from the avatar); every control that is off has its reason as its tooltip.
##
## What it asks of the radio (scripts/sim/radio.gd): `build_willingness(building_id)` ({"ok", "why", "plot", "cost", "note"}) and
## `request_build(building_id, args)` ({"ok", "line", "why", "plot", and "who" (a person's id, optional: the lead builder, whose first
## name goes before the line)}). `options` (all optional): "open_radio" (a Callable(page, opts): the way to another page; the default is
## `host.open_radio`).

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const BuildScreen := preload("res://scripts/ui/build_screen.gd")

## The second press on Demolish must come within this many seconds (real time, not the rules' time).
const CONFIRM_S := BuildScreen.CONFIRM_S
## The answer to an order stays this many seconds (real time).
const ANSWER_S := 6.0
## The Lots page of the modal screen, which "Streets and map..." opens.
const LOTS_PAGE := BuildScreen.LOTS_PAGE
## The list is at least this tall (it scrolls). The panel is as tall as its page asks (radio_panel.gd `fit`) and scrolls a page that asks for
## more than the window has, foot and all; this page scrolls its list instead, and keeps the foot where it is: the list is at most the
## window's height less PANEL_RESERVE (the clock above the panel, the toolbar below it, its tabs and its frame: what is round the page)
## and less the page's own head and foot. Should the panel still have to scroll the page (it knows its room better than this does), the
## list gives up what was missing (`_squeeze`) until the window changes. A button is this tall, a slip's meter this tall.
const MIN_LIST_H := 120.0
const PANEL_RESERVE := 336.0
const BUTTON_H := 30.0
const METER_H := 6.0

var host
var sim_getter: Callable
var options := {}
## plot id -> {"id", "plot", "bid" (the building the plot is the home of), "item" (the slip and, when chosen, the detail), "slip", "button",
## "name", "state", "meter"}, in the order of the data (the same as the modal screen's).
var rows := {}
## The plot that is chosen ("" when none: its detail is shut).
var selected := ""
## Demolish has been pressed once and waits for the second (for the seconds that are left).
var armed := false
var armed_left := 0.0
## What the last order, cancel or demolish said: {"plot", "text", "color", "left"}; {} when nothing is up.
var answer := {}
var caption_label: Label
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var stock_label: Label
var housing_label: Label
var full_button: Button
var streets_button: Button
## The detail of the chosen slip (one node, put under the slip that is chosen) and its parts.
var detail: PanelContainer
var gives_label: Label
var where_label: Label
var cost_row: HFlowContainer
var scrap_label: Label
var work_label: Label
var site_box: VBoxContainer
var site_meter
var site_percent: Label
var site_done: Label
var site_crew: Label
var site_note: Label
var note_label: Label
var jobs_button: Button
var order_button: Button
var cancel_button: Button
var demolish_button: Button
var why_label: Label
var answer_label: Label
var lots_on := false
var _squeeze := 0.0
var _squeeze_for := 0.0
var _squeeze_frame := 0
var _marked := ""
var _sig := ""
var _struct := ""
var _built := false


func setup(p_host, p_sim_getter: Callable, p_options: Dictionary = {}) -> void:
	host = p_host
	sim_getter = p_sim_getter
	options = p_options
	if _built:
		return
	_built = true
	set_process(false)
	_build()
	visibility_changed.connect(_on_visibility_changed)
	tree_exiting.connect(_clear_mark)
	refresh(true)


# ----------------------------------------------------------------- the sim --

func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _build_module():
	var s = _sim()
	return s.build if s != null and s.get("build") != null else null


func _radio():
	var s = _sim()
	return s.radio if s != null and s.get("radio") != null else null


## What the radio says of ordering a building now ({"ok", "why", "plot", "cost", "note"}); a game with no radio that knows it says no.
func _willingness(bid: String, cache: Dictionary = {}) -> Dictionary:
	if cache.has(bid):
		return cache[bid]
	var w := {"ok": false, "why": "nobody is on the radio", "plot": "", "cost": 0, "note": ""}
	var radio = _radio()
	if radio != null and radio.has_method("build_willingness"):
		w = Dictionary(radio.build_willingness(bid)).duplicate()
	cache[bid] = w
	return w


## The plots that get a slip: those of the yard and of the lots that are claimed, and not a wall across a street (lots have their own page).
func _slip_plots() -> Array:
	var out: Array = []
	var build = _build_module()
	if build == null:
		return out
	for pl in build.plots():
		if String(pl.kind) != "mouth":
			out.append(pl)
	return out


## The slip an id means: a home's id is its own slip; a building's id is its site being built, else the home an order would go to, else the
## first that stands; "" when there is no slip for it.
func plot_of(id: String) -> String:
	var build = _build_module()
	if build == null or id == "":
		return ""
	if rows.has(id):
		return id
	if build.building(id).is_empty():
		return ""
	var homes: Array = []
	for pid in rows:
		if String(rows[pid].bid) == id:
			homes.append(String(pid))
	for pid in homes:
		if not build.plot(pid).site.is_empty():
			return pid
	var next := String(build.home_for(id))
	if rows.has(next):
		return next
	for pid in homes:
		if String(build.plot(pid).building) == id:
			return pid
	return String(homes[0]) if not homes.is_empty() else ""


## The building an id means (a home's or a building's own): "" when there is no such building.
func building_of(id: String) -> String:
	var build = _build_module()
	if build == null:
		return ""
	var pl: Dictionary = build.plot(id)
	if not pl.is_empty():
		return String(pl.get("home", ""))
	return id if not build.building(id).is_empty() else ""


## The slips of a building (its homes), in order.
func slips_of(building_id: String) -> Array:
	var out: Array = []
	for pid in rows:
		if String(rows[pid].bid) == building_id:
			out.append(String(pid))
	return out


## Why this building (its next order) or this slip (a home) cannot be ordered now, in the simulation's own words ("" when it can).
func reason_for(id: String) -> String:
	var build = _build_module()
	if build == null:
		return "there is no game"
	var pid := id if not build.plot(id).is_empty() else ""
	var bid := building_of(id)
	if bid == "":
		return "there is no such building"
	if pid != "":
		var pl: Dictionary = build.plot(pid)
		if String(pl.building) != "" or not pl.site.is_empty():
			return ""
		return _reason_of_plot(pl, {})
	return String(_willingness(bid).get("why", ""))


func _reason_of_plot(pl: Dictionary, cache: Dictionary) -> String:
	var build = _build_module()
	var id := String(pl.id)
	var bid := String(pl.get("home", ""))
	if String(build.home_for(bid)) == id:
		var w := _willingness(bid, cache)
		if bool(w.get("ok", false)):
			return ""
		var why := String(w.get("why", ""))
		return why if why != "" else "it cannot be ordered now"
	return String(build.why_not(id, bid))


# ------------------------------------------------------------------- build --

func _build() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	caption_label = host._caps("Buildings")
	add_child(caption_label)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.focus_mode = Control.FOCUS_NONE
	list_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.custom_minimum_size = Vector2(0, MIN_LIST_H)
	add_child(list_scroll)
	list_box = host._vbox(4)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list_box)
	list_box.minimum_size_changed.connect(func(): _fit_list.call_deferred())
	_build_detail()
	_build_foot()


func _para(size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = host._label("", Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 80
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A button of the panel: the small one of the radio views, or the gold one for the main choice. Never focused.
func _button(text: String, primary: bool = false) -> Button:
	var b: Button
	if primary:
		b = host._button(text, true)
		b.custom_minimum_size = Vector2(0, BUTTON_H)
		b.add_theme_font_size_override("font_size", 14)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var st: StyleBox = b.get_theme_stylebox(state)
			st.content_margin_left = 14
			st.content_margin_right = 14
	else:
		b = RadioKit.small_button(host, text, BUTTON_H, 13)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _build_foot() -> void:
	var rule := ColorRect.new()
	rule.color = host.LINE2
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	var counts := HFlowContainer.new()
	counts.add_theme_constant_override("h_separation", 14)
	counts.add_theme_constant_override("v_separation", 2)
	counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stock: HBoxContainer = host._hbox(5)
	stock.add_child(_icon_in("scrap", 16, host.INK2))
	stock_label = host._label("", Fonts.cond(700), 15, host.INK)
	stock.add_child(stock_label)
	counts.add_child(stock)
	housing_label = host._label("", Fonts.cond(700), 15, host.INK)
	housing_label.tooltip_text = "The people the compound has beds for: the school's own, the bunk houses' and the tents'"
	housing_label.mouse_filter = Control.MOUSE_FILTER_PASS
	counts.add_child(housing_label)
	add_child(counts)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_button = _button("Full page")
	full_button.tooltip_text = "The whole Build screen over the game (the game waits while it is open)\nKey: Shift+N"
	full_button.pressed.connect(full_page)
	buttons.add_child(full_button)
	streets_button = _button("Streets and map...")
	streets_button.tooltip_text = "The streets round the school: claim a lot, wall its streets, see the map (the full page, on the Lots)"
	streets_button.pressed.connect(open_streets)
	streets_button.visible = false
	buttons.add_child(streets_button)
	add_child(buttons)


func _icon_in(icon_name: String, size_px: int, color: Color) -> Control:
	var t: TextureRect = host._icon(icon_name, size_px, color)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## The detail of a slip, made once and put under the slip that is chosen.
func _build_detail() -> void:
	detail = PanelContainer.new()
	var s: StyleBoxFlat = host._flat(Color(0.0, 0.0, 0.0, 0.28), 5, host.LINE, false)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 9
	detail.add_theme_stylebox_override("panel", s)
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.visible = false
	var col: VBoxContainer = host._vbox(6)
	detail.add_child(col)
	gives_label = _para(13, host.INK)
	col.add_child(gives_label)
	where_label = _para(13, host.INK2)
	col.add_child(where_label)
	cost_row = HFlowContainer.new()
	cost_row.add_theme_constant_override("h_separation", 12)
	cost_row.add_theme_constant_override("v_separation", 0)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrap: HBoxContainer = host._hbox(4)
	scrap.add_child(_icon_in("scrap", 14, host.INK2))
	scrap_label = host._label("", Fonts.cond(700), 14, host.INK)
	scrap.add_child(scrap_label)
	scrap.tooltip_text = "Paid when it is ordered"
	scrap.mouse_filter = Control.MOUSE_FILTER_PASS
	cost_row.add_child(scrap)
	var work: HBoxContainer = host._hbox(4)
	work.add_child(_icon_in("build", 14, host.INK2))
	work_label = host._label("", Fonts.cond(700), 14, host.INK)
	work.add_child(work_label)
	work.tooltip_text = "Hours of work for the Builders at the base rate: a good builder does more than one an hour"
	work.mouse_filter = Control.MOUSE_FILTER_PASS
	cost_row.add_child(work)
	col.add_child(cost_row)
	# a site: how far along, who builds it
	site_box = host._vbox(4)
	var bar: HBoxContainer = host._hbox(8)
	site_meter = BuildScreen.Meter.new()
	site_meter.custom_minimum_size = Vector2(60, 12)
	site_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	site_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	site_meter.track = Color(host.INK, 0.16)
	site_meter.fill = host.ACCENT
	bar.add_child(site_meter)
	site_percent = host._label("0%", Fonts.cond(700), 16, host.INK)
	site_percent.custom_minimum_size.x = 40
	site_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(site_percent)
	site_box.add_child(bar)
	site_done = _para(13, host.INK2)
	site_box.add_child(site_done)
	site_crew = _para(13, host.INFO, 600)
	site_box.add_child(site_crew)
	site_note = _para(12, host.INK3)
	site_box.add_child(site_note)
	col.add_child(site_box)
	# the crew note (advisory) and the way to the Jobs page
	note_label = _para(13, host.INFO, 600)
	col.add_child(note_label)
	jobs_button = _button("Open the Jobs page")
	jobs_button.tooltip_text = "Put someone on the Builders job, on the Jobs page"
	jobs_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	jobs_button.pressed.connect(open_jobs)
	col.add_child(jobs_button)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_button = _button("Order", true)
	order_button.pressed.connect(_on_order_pressed)
	actions.add_child(order_button)
	cancel_button = _button("Cancel the order")
	cancel_button.pressed.connect(cancel)
	actions.add_child(cancel_button)
	demolish_button = _button("Demolish")
	demolish_button.pressed.connect(demolish)
	actions.add_child(demolish_button)
	col.add_child(actions)
	why_label = _para(13, host.WARN, 600)
	col.add_child(why_label)
	answer_label = _para(13, host.INK, 600)
	col.add_child(answer_label)


# ------------------------------------------------------------------- slips --

## The list is made again when the plots that have a slip are not the ones it was made for (a lot was claimed).
func _sync_structure() -> bool:
	var plots := _slip_plots()
	var sig := "%s|" % str(lots_on)
	for pl in plots:
		sig += "%s;" % String(pl.id)
	if sig == _struct:
		return false
	_struct = sig
	if detail.get_parent() != null:
		detail.get_parent().remove_child(detail)
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	rows.clear()
	var sim = _sim()
	var last_lot := "~"
	for pl in plots:
		var lot := String(pl.get("lot", ""))
		if lots_on and lot != last_lot:
			var caption := "In the compound" if lot == "" else String(sim.lots.lot(lot).get("name", lot))
			list_box.add_child(host._caps(caption))
		last_lot = lot
		list_box.add_child(_make_slip(pl))
	if not rows.has(selected):
		selected = ""
	_sig = ""
	return true


## One building's slip: its name over what it is now, with a meter while a site goes up. The slip is a card whose whole face is a
## button (the words sit over it and let the pointer through).
func _make_slip(pl: Dictionary) -> Control:
	var id := String(pl.id)
	var item: VBoxContainer = host._vbox(3)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	for state in ["hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.06 if state == "hover" else 0.12)
		s.set_corner_radius_all(5)
		b.add_theme_stylebox_override(state, s)
	slip.add_child(b)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 5)
	pad.add_theme_constant_override("margin_bottom", 6)
	var inner: VBoxContainer = host._vbox(1)
	var name_label: Label = host._label(String(pl.name), Fonts.cond(700), 16, host.INK)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(name_label)
	var state: Label = _para(13, host.INK2, 600)
	inner.add_child(state)
	var meter = BuildScreen.Meter.new()
	meter.custom_minimum_size = Vector2(40, METER_H)
	meter.track = Color(host.INK, 0.16)
	meter.fill = host.ACCENT
	meter.visible = false
	inner.add_child(meter)
	pad.add_child(inner)
	slip.add_child(pad)
	item.add_child(slip)
	b.pressed.connect(_on_slip_pressed.bind(id))
	b.mouse_entered.connect(_on_slip_hover.bind(id, true))
	b.mouse_exited.connect(_on_slip_hover.bind(id, false))
	rows[id] = {"id": id, "plot": pl, "bid": String(pl.get("home", "")), "item": item, "slip": slip, "button": b, "name": name_label, "state": state, "meter": meter, "chosen": null}
	_style_slip(rows[id], false)
	return item


## A card of the board a little lighter than the panel; gold at the edge while it is the slip that is chosen.
func _style_slip(r: Dictionary, chosen: bool) -> void:
	var s: StyleBoxFlat = host._flat(Color(host.PANEL_HI, 1.0), 5, Color(host.ACCENT, 0.85) if chosen else host.LINE2, false)
	s.set_border_width_all(2 if chosen else 1)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	r.slip.add_theme_stylebox_override("panel", s)
	r.chosen = chosen


## What a slip says now: {"id", "bid", "title", "kind" ("built", "site", "cost", "why"), "state", "progress", "reason", "note"}.
func _slip_model(pl: Dictionary, cache: Dictionary) -> Dictionary:
	var build = _build_module()
	var id := String(pl.id)
	var bid := String(pl.get("home", ""))
	var m := {"id": id, "bid": bid, "title": String(build.title_of(id)), "kind": "", "state": "", "progress": 0.0, "reason": "", "note": ""}
	if String(pl.building) != "":
		m.kind = "built"
		m.state = "Built"
	elif not pl.site.is_empty():
		var share: float = build.progress_of(id)
		m.kind = "site"
		m.state = "Going up: %d%%" % mini(99, floori(share * 100.0))
		m.progress = share
	else:
		var reason := _reason_of_plot(pl, cache)
		if String(build.home_for(bid)) == id:
			m.note = String(_willingness(bid, cache).get("note", ""))
		if reason == "":
			var b: Dictionary = build.building(bid)
			m.kind = "cost"
			m.state = "%s scrap, %s builder-hours" % [BuildScreen._num(float(b.scrap)), BuildScreen._num(float(b.work))]
		else:
			m.kind = "why"
			m.state = BuildScreen._sentence(reason).trim_suffix(".")
			m.reason = reason
	return m


func _state_color(kind: String) -> Color:
	match kind:
		"why":
			return host.WARN
		"built":
			return host.OK
		"site":
			return host.INK
	return host.INK2


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


# ----------------------------------------------------------------- refresh --

## The list is as tall as its slips (and the open detail) need, between MIN_LIST_H and what the window leaves it: past that it scrolls.
func _fit_list(calibrate: bool = false) -> void:
	if list_box == null or not is_instance_valid(list_scroll):
		return
	var window_h := 800.0
	if is_instance_valid(host) and host is Control and host.size.y > 0.0:
		window_h = host.size.y
	if absf(window_h - _squeeze_for) > 0.5:
		_squeeze = 0.0
		_squeeze_for = window_h
	var chrome := get_combined_minimum_size().y - list_scroll.get_combined_minimum_size().y
	# the panel has scrolled the whole page for want of room: what was missing comes off the list (once for each time it has laid itself out)
	var holder := get_parent()
	if calibrate and holder is ScrollContainer and holder.is_visible_in_tree() and holder.size.y > 0.0 and Engine.get_process_frames() - _squeeze_frame > 4:
		var missing: float = get_combined_minimum_size().y - float(holder.size.y)
		if missing > 1.0 and list_scroll.custom_minimum_size.y > MIN_LIST_H + 0.5:
			_squeeze += missing
			_squeeze_frame = Engine.get_process_frames()
	var cap := maxf(MIN_LIST_H, window_h - PANEL_RESERVE - chrome - _squeeze)
	var h := clampf(list_box.get_combined_minimum_size().y, MIN_LIST_H, cap)
	if absf(list_scroll.custom_minimum_size.y - h) > 0.5:
		list_scroll.custom_minimum_size.y = h


## Brings the page in line with the game: the foot, every slip, the detail. Only what changed is redrawn.
func refresh(force: bool = false) -> void:
	var build = _build_module()
	if build == null or not _built:
		return
	var sim = _sim()
	lots_on = sim.get("lots") != null and sim.lots.on
	if _sync_structure():
		force = true
	var cache := {}
	var models := {}
	for id in rows:
		models[id] = _slip_model(rows[id].plot, cache)
	var sig := "%s|%s|%d|%d|%s|%s|%s;%s;%s" % [selected, str(armed), roundi(float(sim.stock.scrap) * 10.0), build.housing(), _crew_signature(), String(sim.phase), str(sim.bell_rung), str(models.values()), str(answer.get("text", ""))]
	if sig == _sig and not force:
		_fit_list(not force)
		_ensure_mark()
		return
	_sig = sig
	stock_label.text = "Scrap in the stores: %d" % int(float(sim.stock.scrap))
	var beds: int = build.housing()
	housing_label.text = "Beds for %d %s" % [beds, "person" if beds == 1 else "people"]
	streets_button.visible = lots_on
	# (a settlement game's list has its own captions: "In the compound", the lots' names)
	caption_label.visible = not lots_on
	for id in rows:
		_refresh_slip(rows[id], models[id])
	_refresh_detail(models)
	_fit_list(not force)
	_ensure_mark()


func _refresh_slip(r: Dictionary, m: Dictionary) -> void:
	_set_text(r.name, String(m.title), host.INK)
	_set_text(r.state, String(m.state), _state_color(String(m.kind)))
	var meter = r.meter
	meter.visible = String(m.kind) == "site"
	meter.value = float(m.progress)
	meter.queue_redraw()
	var chosen: bool = String(r.id) == selected
	if r.chosen != chosen:
		_style_slip(r, chosen)
	r.button.tooltip_text = "%s: %s" % [String(m.title), String(m.state)]


## The detail under the chosen slip (or none): by what the building is now.
func _refresh_detail(models: Dictionary) -> void:
	if selected == "" or not rows.has(selected):
		if detail.get_parent() != null:
			detail.get_parent().remove_child(detail)
		detail.visible = false
		return
	var build = _build_module()
	var r: Dictionary = rows[selected]
	if detail.get_parent() != r.item:
		if detail.get_parent() != null:
			detail.get_parent().remove_child(detail)
		r.item.add_child(detail)
	detail.visible = true
	var m: Dictionary = models[selected]
	var pl: Dictionary = build.plot(selected)
	var standing := String(pl.building) != ""
	var going_up: bool = not pl.site.is_empty()
	var bid: String = String(pl.building) if standing else (String(pl.site.building) if going_up else String(r.bid))
	var b: Dictionary = build.building(bid)
	gives_label.text = String(b.get("blurb", ""))
	var why := String(pl.get("why", ""))
	where_label.text = "Where it goes: %s. %s" % [String(pl.name), why] if why != "" else "Where it goes: %s." % String(pl.name)
	# not built: the price, the crew, Order
	var free := not standing and not going_up
	cost_row.visible = free
	if free:
		scrap_label.text = "%s scrap" % BuildScreen._num(float(b.scrap))
		work_label.text = "%s builder-hours" % BuildScreen._num(float(b.work))
	var note := String(m.note)
	note_label.text = note
	note_label.visible = free and note != ""
	var crew_empty: bool = _sim().jobs.crew_of("builders").is_empty()
	jobs_button.visible = free and note != "" and crew_empty
	order_button.visible = free
	var reason := String(m.reason)
	order_button.disabled = reason != ""
	order_button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if reason != "" else Control.CURSOR_POINTING_HAND
	order_button.tooltip_text = BuildScreen._sentence(reason) if reason != "" else "Order the %s: %s scrap now, then the Builders raise it where it goes" % [String(b.get("name", bid)).to_lower(), BuildScreen._num(float(b.get("scrap", 0)))]
	# a site: how far along and who builds it
	site_box.visible = going_up
	cancel_button.visible = going_up
	if going_up:
		var share: float = build.progress_of(selected)
		site_meter.value = share
		site_meter.queue_redraw()
		site_percent.text = "%d%%" % mini(99, floori(share * 100.0))
		var work := float(pl.site.work)
		var done := minf(float(pl.site.progress), work)
		site_done.text = "%s of %s builder-hours done." % [BuildScreen._num(done, 1), BuildScreen._num(work)]
		var line := _crew_line(pl)
		site_crew.text = String(line.text)
		jobs_button.visible = bool(line.no_crew)
		site_note.text = _night_note()
		site_note.visible = site_note.text != ""
		var back := _refund_of_site(pl)
		cancel_button.text = "Cancel the order (+%s scrap)" % BuildScreen._num(back)
		cancel_button.tooltip_text = ("No work has been done: all the scrap comes back" if float(pl.site.progress) <= 0.0 else "Work has begun: half the scrap comes back") + "\nThe plot is free again"
	# a building that stands: Demolish
	demolish_button.visible = standing
	var refused := ""
	if standing:
		refused = String(build.why_not_demolish(selected))
		var back2 := float(b.scrap) * float(build.REFUND_SHARE)
		demolish_button.disabled = refused != ""
		demolish_button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if refused != "" else Control.CURSOR_POINTING_HAND
		if armed and refused == "":
			demolish_button.text = "Press again to demolish (+%s scrap)" % BuildScreen._num(back2)
			demolish_button.tooltip_text = "Press again within %d seconds, or leave it: nothing is taken down until then" % int(CONFIRM_S)
		else:
			demolish_button.text = "Demolish (+%s scrap)" % BuildScreen._num(back2)
			demolish_button.tooltip_text = BuildScreen._sentence(refused) if refused != "" else "Take the %s down: half of its scrap comes back, its effects end and the plot is free\nTwo presses: the second within %d seconds" % [String(b.get("name", bid)).to_lower(), int(CONFIRM_S)]
	why_label.text = BuildScreen._sentence(refused)
	why_label.visible = refused != ""
	# what the last order, cancel or demolish said (for this slip)
	var shown: bool = not answer.is_empty() and String(answer.plot) == selected
	answer_label.visible = shown
	if shown:
		answer_label.text = String(answer.text)
		answer_label.add_theme_color_override("font_color", answer.color)


## What Cancel gives back (the same sum the buildings module works out).
func _refund_of_site(pl: Dictionary) -> float:
	var share := 1.0 if float(pl.site.progress) <= 0.0 else float(_build_module().REFUND_SHARE)
	return float(pl.site.scrap) * share


## The Builders as the estimate sees them: who is on the job, whether they can work, and how fast.
func _crew_signature() -> String:
	var sim = _sim()
	var sig := String(sim.build.active_site().get("id", ""))
	for p in sim.jobs.crew_of("builders"):
		sig += "|%s,%s,%s,%d" % [p.id, p.away != null, p.downed, roundi(float(sim.build.rate(p)) * 100.0)]
	return sig


## The line about who is building the site: {"text", "no_crew"}. For the site the crew works on now, their names and about how long it will
## take at the present pace; for one that waits its turn, which comes first. (The modal screen's own words and sums.)
func _crew_line(pl: Dictionary) -> Dictionary:
	var sim = _sim()
	var build = sim.build
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
		return {"text": "%s cannot build just now (away or hurt)." % BuildScreen._names(crew), "no_crew": false}
	var per_hour := 0.0
	for p in able:
		per_hour += float(build.rate(p))
	var left := maxf(0.0, float(pl.site.work) - float(pl.site.progress))
	return {"text": "%s: %s at the present pace." % [BuildScreen._names(able), BuildScreen._time_text(left / maxf(per_hour, 0.001))], "no_crew": false}


## At night the site waits: they hold the posts.
func _night_note() -> String:
	var sim = _sim()
	var phase := String(sim.phase)
	var night: bool = phase == "night" or phase == "dawn" or (phase == "dusk" and bool(sim.bell_rung))
	return "It is night: the Builders hold the posts, and the site waits for the morning." if night else ""


# ------------------------------------------------------------------ choosing --

## A slip was pressed: it opens; pressed again, it closes.
func _on_slip_pressed(id: String) -> void:
	_play("ui_click")
	if selected == id:
		_choose("")
	else:
		_choose(id)


## Chooses a building, by its id or its home's (the slip opens): false when there is no slip for it.
func select_building(id: String) -> bool:
	var pid := plot_of(id)
	if pid == "":
		return false
	_choose(pid)
	return true


func _choose(pid: String) -> void:
	if pid == selected:
		return
	if armed:
		_disarm()
	selected = pid
	if not answer.is_empty() and String(answer.plot) != pid:
		answer = {}
	_sig = ""
	refresh(true)
	if pid != "":
		_reveal.call_deferred()
	_mark(pid)


## The panel (or the HUD) asks for a building: it is chosen and brought into view.
func focus_on(id: String) -> void:
	select_building(id)


func _reveal() -> void:
	if is_inside_tree() and rows.has(selected):
		list_scroll.ensure_control_visible(rows[selected].item)


# --------------------------------------------------------------------- marks --

## The pointer is on a slip (or has left it): its home is marked in the yard; when it has left, the chosen slip's again.
func _on_slip_hover(id: String, on: bool) -> void:
	if on:
		_mark(id)
	elif _marked == id:
		_mark(selected)


## The home of a plot is marked in the yard ("" marks nothing). A page that is not shown marks nothing.
func _mark(pid: String) -> void:
	if not is_visible_in_tree():
		return
	_set_mark(pid)


func _set_mark(pid: String) -> void:
	if pid == _marked and _hud_mark() == pid:
		return
	_marked = pid
	if is_instance_valid(host) and host.has_method("set_build_hover"):
		host.set_build_hover({"plot": pid} if pid != "" else {})


func _hud_mark() -> String:
	var marks = host.get("build_hover") if is_instance_valid(host) else null
	return String(marks.get("plot", "")) if marks is Dictionary else ""


## What is marked now ({"plot": id} or {}).
func marks() -> Dictionary:
	return {"plot": _marked} if _marked != "" else {}


## While the page is shown its mark stands (the modal screen, closing, clears the world's: this page puts its own back).
func _ensure_mark() -> void:
	if not is_visible_in_tree() or not is_instance_valid(host):
		return
	if host.get("build_screen") != null:
		return
	var want := selected if _marked == "" or _marked == selected else _marked
	if _hud_mark() != want:
		_marked = ""
		_set_mark(want)


func _clear_mark() -> void:
	if _marked != "" and is_instance_valid(host) and host.has_method("set_build_hover"):
		host.set_build_hover({})
	_marked = ""


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_sig = ""
		refresh(true)
		_mark(selected)
	else:
		if armed:
			_disarm()
		_clear_mark()


# -------------------------------------------------------------------- acting --

## Orders a building (its id, or its home's): the radio is asked, the Builders agree and a site goes up at its home. The answer is the lead
## builder's words; a refusal says why, in amber. Returns what the radio said ({"ok", "line", "why", "plot"}).
func order(id: String) -> Dictionary:
	refresh()
	var bid := building_of(id)
	var radio = _radio()
	var res := {"ok": false, "line": "", "why": "there is no such building", "plot": ""}
	if bid != "" and radio != null and radio.has_method("request_build"):
		res = Dictionary(radio.request_build(bid, {})).duplicate()
	elif bid != "":
		res.why = "nobody is on the radio"
	# the slip it is about is opened, so that the answer is seen where it was asked
	var pid := String(res.get("plot", ""))
	if pid == "" or not rows.has(pid):
		pid = plot_of(id)
	if pid != "" and selected != pid:
		_choose(pid)
	if bool(res.get("ok", false)):
		_say(pid, _lead_line(res), _lead_color(res))
		_play("ui_confirm")
	else:
		_say(pid, BuildScreen._sentence(String(res.get("why", ""))), host.WARN)
		_play("ui_error")
	refresh(true)
	return res


func _on_order_pressed() -> void:
	if selected != "":
		order(selected)


## Green when the lead builder is willing (the radio's tone for them, or the result's own), plain when they are grudging or when nobody is.
func _lead_color(res: Dictionary) -> Color:
	var tone := String(res.get("tone", ""))
	var who := String(res.get("who", ""))
	var radio = _radio()
	if tone == "" and who != "" and radio != null and radio.has_method("tone_of"):
		for p in _sim().people:
			if String(p.id) == who:
				tone = String(radio.tone_of(p))
	if tone == "" and who == "":
		return host.INK
	return host.OK if tone == "willing" or tone == "" else host.INK


## "Dez: On it." (the first name of the lead builder, when the radio says who; else the line as it is).
func _lead_line(res: Dictionary) -> String:
	var line := String(res.get("line", ""))
	var who := String(res.get("who", ""))
	var sim = _sim()
	if who != "":
		for p in sim.people:
			if String(p.id) == who and not line.begins_with(String(p.first)):
				return "%s: %s" % [String(p.first), line]
	return line if line != "" else "Ordered."


## Stops the site on the chosen slip: all the scrap back if no work was done, else half. False if there is none.
func cancel() -> bool:
	var build = _build_module()
	if build == null or selected == "":
		return false
	var pl: Dictionary = build.plot(selected)
	var back := _refund_of_site(pl) if not pl.is_empty() and not pl.site.is_empty() else 0.0
	if not build.cancel(selected):
		_say(selected, "There is nothing to cancel.", host.WARN)
		_play("ui_error")
		refresh(true)
		return false
	_say(selected, "Cancelled: %s scrap back." % BuildScreen._num(back), host.INK)
	_play("ui_click")
	refresh(true)
	return true


## Demolish, in two presses: the first arms the button (it says so), the second, within CONFIRM_S seconds, takes the building down. True when
## it came down.
func demolish() -> bool:
	var build = _build_module()
	if build == null or selected == "":
		return false
	var why := String(build.why_not_demolish(selected))
	if why != "":
		_say(selected, BuildScreen._sentence(why), host.WARN)
		_play("ui_error")
		refresh(true)
		return false
	if not armed:
		armed = true
		armed_left = CONFIRM_S
		set_process(true)
		_play("ui_click")
		refresh(true)
		return false
	_disarm()
	var pl: Dictionary = build.plot(selected)
	var back := float(build.building(String(pl.building)).scrap) * float(build.REFUND_SHARE)
	if not build.demolish(selected):
		_say(selected, "It cannot be taken down.", host.WARN)
		refresh(true)
		return false
	_say(selected, "Taken down: %s scrap back." % BuildScreen._num(back), host.INK)
	_play("ui_confirm")
	refresh(true)
	return true


func _disarm() -> void:
	if not armed:
		return
	armed = false
	armed_left = 0.0
	_sig = ""
	_maybe_idle()
	if _built:
		refresh(true)


func _say(pid: String, text: String, color: Color) -> void:
	answer = {"plot": pid, "text": text, "color": color, "left": ANSWER_S}
	set_process(true)


func _maybe_idle() -> void:
	set_process(armed or not answer.is_empty())


## Real time passes for the armed button and the answer (the rules do not wait for this page, but this is not their clock either).
func _process(delta: float) -> void:
	var changed := false
	if armed:
		armed_left -= delta
		if armed_left <= 0.0:
			_disarm()
	if not answer.is_empty():
		answer.left = float(answer.left) - delta
		if float(answer.left) <= 0.0:
			answer = {}
			changed = true
	_maybe_idle()
	if changed:
		refresh(true)


## The Builders' site waits for nobody: the Jobs page, with the Builders' station marked.
func open_jobs() -> void:
	var g = options.get("open_radio")
	if g is Callable and g.is_valid():
		g.call("jobs", {"focus": "builders"})
	elif is_instance_valid(host) and host.has_method("open_radio"):
		host.open_radio("jobs", {"focus": "builders"})
	elif is_instance_valid(host) and host.has_method("open_jobs"):
		host.open_jobs()


## The full modal page of the same name (the old screen).
func full_page() -> void:
	if host != null and host.has_method("open_build"):
		host.open_build()


## The same screen on its Lots page: the streets, the claims, the walls and the map (a settlement game only).
func open_streets() -> void:
	if lots_on and host != null and host.has_method("open_build"):
		host.open_build(LOTS_PAGE)


func _play(sound_name: String) -> void:
	if is_instance_valid(host) and host.has_method("ui_sound"):
		host.ui_sound(sound_name)
