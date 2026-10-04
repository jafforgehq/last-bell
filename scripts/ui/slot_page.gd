extends VBoxContainer
## The Build page of the radio panel in the town (One House, WP7): the PERIMETER of the claimed house. The school's page lists buildings; the
## town's Build page is the places round the house where something can go up. At the top a plan of the lot (slot_plan.gd) with a marker for each slot,
## under it the slot that is picked, and under that the list of every slot (a click on a row picks it as a click on the plan does).
##
## For the slot that is picked, by what it is now:
##   - locked: why, in the rules' own words ("Opens when 3 people are here"); nothing to press
##   - open (and fallen, for it can be raised again): the kits it can have, each with what it costs in scrap and builder-hours and how many hit points
##     it has; a kit that cannot be had says why in amber; **Order** (`perimeter.order(slot, kit)`)
##   - ordered or going up: **Cancel** (`perimeter.cancel`)
##   - built: its hit points, and **Demolish** (the first press arms it and says what comes back, the second, within CONFIRM_S seconds, does it)
##
## What it asks of `sim.perimeter` (plan 2.2, WP5): `slots()` ([{"id", "kind", "name", "rect", "state": "locked|open|ordered|building|built|broken", "kit",
## "hp", "max_hp", "unlock": {"crew": n}, "why_not", "plot"}]), `kits_for(slot_id)` ([{"id", "name", "blurb", "scrap", "work", "hp", "ok", "why"}]), `order`,
## `cancel`, `demolish`. And of the rest, only to draw the plan: `sim.base.layout` ("plot", "front", "posts"), `sim.houses.house(id).rect`, `sim.stock.scrap`.
## It writes nothing but through those three calls, and a game with no perimeter says "Nothing to build yet".
##
## One of the radio panel's pages: `setup(host, sim_getter, options)`, `refresh()` (each HUD update while it is shown; only what changed is redrawn),
## `focus_on(id)` (a slot's id or its plot's), `full_page()` (the town has no modal Build page: it does nothing). Every control is FOCUS_NONE: the panel never
## steals the keyboard from the avatar.

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const BuildScreen := preload("res://scripts/ui/build_screen.gd")
const SlotPlan := preload("res://scripts/ui/slot_plan.gd")

## The second press on Demolish must come within this many seconds (real time).
const CONFIRM_S := 4.0
## The answer to an order stays this many seconds (real time).
const ANSWER_S := 6.0
const BUTTON_H := 30.0
const STATE_WORD := {"locked": "Locked", "open": "Open", "ordered": "Ordered", "building": "Going up", "built": "Built", "broken": "Fallen"}
const EMPTY_UNCLAIMED := "Nothing to build yet. Claim the house, and the places round it show here: a fence, a gate, a tower, a floodlight."
const EMPTY_CLAIMED := "There is nothing to build round the house yet."
const KIND_WORD := {"fence": "Fence", "gate": "Gate", "tower": "Tower", "floodlight": "Floodlight", "door": "Door"}

var host
var sim_getter: Callable
var options := {}
var plan
var detail: PanelContainer
var detail_col: VBoxContainer
var list_box: VBoxContainer
var list_caption: Label
var empty_label: Label
var stock_label: Label
var people_label: Label
## slot id -> {"id", "slot", "slip", "state"} for the list's rows.
var rows := {}
## The slot that is picked ("" for none) and the kit chosen for it.
var selected := ""
var kit_id := ""
## The buttons of the detail now (null when it has none).
var order_button: Button
var cancel_button: Button
var demolish_button: Button
## What the last order, cancel or demolish said: {"slot", "text", "color", "left"}; {} when nothing is up.
var answer := {}
var armed := false
var armed_left := 0.0
var _sig := ""
var _marked := ""
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


func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _per():
	var s = _sim()
	return s.get("perimeter") if s != null else null


## The slots now, or [] in a game that has no perimeter.
func slots() -> Array:
	var per = _per()
	if per == null or not per.has_method("slots"):
		return []
	var got = per.slots()
	return got if got is Array else []


## Whether the house has been claimed (the page says what to do first when it has not).
func _claimed() -> bool:
	var s = _sim()
	var b = s.get("base") if s != null else null
	return b != null and b.get("claimed") == true


func slot_of(id: String) -> Dictionary:
	for s in slots():
		if String(s.get("id", "")) == id or String(s.get("plot", "")) == id and id != "":
			return s
	return {}


# ------------------------------------------------------------------------- build --

func _build() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_caps("Round the house"))
	plan = SlotPlan.new()
	plan.setup(host)
	plan.picked.connect(select)
	plan.hovered.connect(_on_hover)
	add_child(plan)
	empty_label = _para(14, host.INK2, 400)
	empty_label.text = EMPTY_UNCLAIMED
	empty_label.visible = false
	add_child(empty_label)
	detail = PanelContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st: StyleBoxFlat = host._flat(Color(host.PANEL_HI, 1.0), 5, host.LINE2, false)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 9
	detail.add_theme_stylebox_override("panel", st)
	detail_col = host._vbox(5)
	detail.add_child(detail_col)
	add_child(detail)
	list_caption = _caps("Every place")
	add_child(list_caption)
	list_box = host._vbox(3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(list_box)
	_build_foot()


func _caps(text: String) -> Label:
	return host._label(text.to_upper(), Fonts.cond(600, 1), 14, host.INK3)


func _para(size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = host._label("", Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 80
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, primary: bool = false) -> Button:
	var b: Button
	if primary:
		b = host._button(text, true)
		b.custom_minimum_size = Vector2(0, BUTTON_H)
		b.add_theme_font_size_override("font_size", 15)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var st: StyleBox = b.get_theme_stylebox(state)
			st.content_margin_left = 14
			st.content_margin_right = 14
	else:
		b = RadioKit.small_button(host, text, BUTTON_H, 14)
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
	counts.add_theme_constant_override("h_separation", 16)
	counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stock: HBoxContainer = host._hbox(5)
	var ic: TextureRect = host._icon("scrap", 16, host.INK2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stock.add_child(ic)
	stock_label = host._label("", Fonts.cond(700), 15, host.INK)
	stock.add_child(stock_label)
	counts.add_child(stock)
	people_label = host._label("", Fonts.cond(700), 15, host.INK)
	people_label.tooltip_text = "The people in the house, you included: more of them open more places round it"
	people_label.mouse_filter = Control.MOUSE_FILTER_PASS
	counts.add_child(people_label)
	add_child(counts)


# ------------------------------------------------------------------------ the words --

static func _num(x: float) -> String:
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x


## "5 scrap, 3 builder-hours, 120 hit points" for a kit.
static func cost_text(kit: Dictionary) -> String:
	var parts: Array = []
	if kit.has("scrap"):
		parts.append("%s scrap" % _num(float(kit.scrap)))
	if kit.has("work"):
		parts.append("%s builder-hours" % _num(float(kit.work)))
	if kit.has("hp"):
		parts.append("%s hit points" % _num(float(kit.hp)))
	return ", ".join(parts)


func crew_now() -> int:
	var s = _sim()
	if s == null:
		return 0
	var sc = s.get("scenario")
	if sc != null and sc.has_method("crew_count"):
		return int(sc.crew_count())
	var n := 0
	if s.get("people") != null:
		for p in s.people:
			if not p.dead and not p.turned:
				n += 1
	return n


## Why a locked slot is locked, in the module's own words, else from its unlock rule.
func locked_reason(s: Dictionary) -> String:
	var why := String(s.get("why_not", ""))
	if why != "":
		return why
	var unlock = s.get("unlock", {})
	if unlock is Dictionary and unlock.has("crew"):
		var need := int(unlock.crew)
		return "Opens when %d people are here (%d now)" % [need, crew_now()]
	return "Not yet"


## The one line a slot's row says: what stands there, or what is the matter.
func line_of(s: Dictionary) -> String:
	var state := String(s.get("state", "open"))
	match state:
		"locked":
			return locked_reason(s)
		"built":
			var hp := float(s.get("hp", 0.0))
			var mx := float(s.get("max_hp", 0.0))
			var kit := String(s.get("kit_name", s.get("kit", "")))
			return ("%s, %s of %s hit points" % [kit.capitalize(), _num(hp), _num(mx)]) if mx > 0.0 else kit.capitalize()
		"ordered":
			return "Ordered: waiting for the Builders"
		"building":
			return "Going up"
		"broken":
			return "Fallen: it can be raised again"
		_:
			return "Free: pick something to build"


func state_color(state: String) -> Color:
	return SlotPlan.STATE_COLOR.get(state, host.INK3)


# ------------------------------------------------------------------------ the sim -> the page --

## Brings the page up to date; without `force` only if something it shows changed.
func refresh(force: bool = false) -> void:
	if host == null or not _built:
		return
	var list := slots()
	var per = _per()
	var sig := _signature(list)
	_tick_labels()
	if sig == _sig and not force:
		return
	_sig = sig
	if selected != "" and slot_of(selected).is_empty():
		selected = ""
		kit_id = ""
	var any := not list.is_empty()
	empty_label.text = EMPTY_CLAIMED if _claimed() else EMPTY_UNCLAIMED
	empty_label.visible = not any
	list_caption.visible = any
	plan.visible = any
	detail.visible = any
	_fill_plan(list)
	_rebuild_list(list)
	_rebuild_detail(slot_of(selected), per)
	_mark_selected()


func _signature(list: Array) -> String:
	var sig := "%s|%s|%s|%s|%d|%s" % [selected, kit_id, str(armed), String(answer.get("text", "")), crew_now(), str(_claimed())]
	for s in list:
		sig += "|%s,%s,%s,%s,%s" % [String(s.get("id", "")), String(s.get("state", "")), String(s.get("kit", "")), str(snappedf(float(s.get("hp", 0.0)), 0.5)), String(s.get("why_not", ""))]
	var sim = _sim()
	if sim != null and sim.get("stock") != null:
		sig += "|%d" % roundi(float(sim.stock.scrap))
	return sig


func _tick_labels() -> void:
	var sim = _sim()
	if sim != null and sim.get("stock") != null:
		stock_label.text = "%d scrap" % roundi(float(sim.stock.scrap))
	people_label.text = "%d in the house" % crew_now()


func _fill_plan(list: Array) -> void:
	var sim = _sim()
	var base = sim.get("base") if sim != null else null
	var layout: Dictionary = base.layout if base != null and base.get("layout") is Dictionary else {}
	var house_rect = null
	var houses = sim.get("houses") if sim != null else null
	if base != null and houses != null and houses.has_method("house") and base.get("house") != null and int(base.house) >= 0:
		var hh = houses.house(int(base.house))
		if hh is Dictionary:
			house_rect = hh.get("rect")
	var posts: Array = []
	for p in layout.get("posts", []):
		if p is Dictionary and p.get("pos") is Array and (p.pos as Array).size() >= 2:
			posts.append(Vector2(float(p.pos[0]) + 0.5, float(p.pos[1]) + 0.5))
	plan.selected = selected
	plan.set_data({"lot": layout.get("plot"), "house": house_rect, "front": String(layout.get("front", "S")), "slots": list, "posts": posts})


func _rebuild_list(list: Array) -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	rows.clear()
	for s in list:
		list_box.add_child(_make_row(s))


func _make_row(s: Dictionary) -> Control:
	var id := String(s.get("id", ""))
	var state := String(s.get("state", "open"))
	var chosen := id == selected
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = host._flat(Color(host.PANEL_HI, 1.0), 5, Color(host.ACCENT, 0.85) if chosen else host.LINE2, false)
	sb.set_border_width_all(2 if chosen else 1)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	slip.add_theme_stylebox_override("panel", sb)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for st in ["hover", "pressed"]:
		var hv := StyleBoxFlat.new()
		hv.bg_color = Color(1, 1, 1, 0.06 if st == "hover" else 0.12)
		hv.set_corner_radius_all(5)
		b.add_theme_stylebox_override(st, hv)
	slip.add_child(b)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 5)
	var inner: VBoxContainer = host._vbox(0)
	var head: HBoxContainer = host._hbox(8)
	var name_label: Label = host._label(String(s.get("name", KIND_WORD.get(String(s.get("kind", "")), "Place"))), Fonts.cond(700), 16, host.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_label)
	var chip: Label = host._label(String(STATE_WORD.get(state, state)).to_upper(), Fonts.cond(700, 1), 14, state_color(state))
	head.add_child(chip)
	inner.add_child(head)
	var line: Label = _para(14, host.WARN if state == "locked" else host.INK2, 400)
	line.text = line_of(s)
	inner.add_child(line)
	pad.add_child(inner)
	slip.add_child(pad)
	b.pressed.connect(select.bind(id))
	b.mouse_entered.connect(_on_hover.bind(id))
	b.mouse_exited.connect(_on_hover.bind(""))
	rows[id] = {"id": id, "slot": s, "slip": slip, "state": chip, "line": line, "button": b}
	return slip


# ----------------------------------------------------------------------- the detail --

func _rebuild_detail(s: Dictionary, per) -> void:
	for c in detail_col.get_children():
		detail_col.remove_child(c)
		c.queue_free()
	order_button = null
	cancel_button = null
	demolish_button = null
	if s.is_empty():
		var hint := _para(14, host.INK2, 400)
		hint.text = "Pick a place on the plan, or in the list. A gold square is free; a grey one waits for more people."
		detail_col.add_child(hint)
		return
	var id := String(s.get("id", ""))
	var state := String(s.get("state", "open"))
	var head: HBoxContainer = host._hbox(8)
	var name_label: Label = host._label(String(s.get("name", "Place")), Fonts.cond(700), 18, host.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(host._label(String(STATE_WORD.get(state, state)).to_upper(), Fonts.cond(700, 1), 14, state_color(state)))
	detail_col.add_child(head)
	match state:
		"locked":
			var why := _para(14, host.WARN, 600)
			why.text = locked_reason(s)
			detail_col.add_child(why)
		"open", "broken":
			_build_kits(id, per, state == "broken")
		"ordered", "building":
			var note := _para(14, host.INK2, 400)
			note.text = "The Builders raise it when they can reach it." if state == "ordered" else "The Builders are at it."
			detail_col.add_child(note)
			cancel_button = _button("Cancel")
			cancel_button.tooltip_text = "Take the order back: the scrap comes back (half of it once the work has begun)"
			cancel_button.pressed.connect(_on_cancel.bind(id))
			detail_col.add_child(cancel_button)
		"built":
			var hp := float(s.get("hp", 0.0))
			var mx := float(s.get("max_hp", 0.0))
			var kit_name := String(s.get("kit_name", s.get("kit", "")))
			var words := _para(14, host.INK, 400)
			words.text = "%s: %s of %s hit points" % [kit_name.capitalize(), _num(hp), _num(mx)] if mx > 0.0 else kit_name.capitalize()
			detail_col.add_child(words)
			if mx > 0.0:
				var meter = BuildScreen.Meter.new()
				meter.custom_minimum_size = Vector2(40, 6)
				meter.track = Color(host.INK, 0.16)
				meter.fill = host.OK if hp / mx > 0.5 else host.WARN
				meter.value = clampf(hp / mx, 0.0, 1.0)
				detail_col.add_child(meter)
			demolish_button = _button("Demolish")
			demolish_button.tooltip_text = "Take it down: half the scrap comes back"
			demolish_button.pressed.connect(_on_demolish.bind(id))
			if armed:
				demolish_button.text = "Press again to take it down"
			detail_col.add_child(demolish_button)
	if not answer.is_empty() and String(answer.get("slot", "")) == id:
		var a := _para(14, answer.get("color", host.INK), 600)
		a.text = String(answer.get("text", ""))
		detail_col.add_child(a)


func _build_kits(slot_id: String, per, fallen: bool) -> void:
	var kits: Array = []
	if per != null and per.has_method("kits_for"):
		var got = per.kits_for(slot_id)
		if got is Array:
			kits = got
	if kits.is_empty():
		var none := _para(14, host.INK2, 400)
		none.text = "There is nothing to build here yet."
		detail_col.add_child(none)
		return
	if fallen:
		var fell := _para(14, host.WARN, 600)
		fell.text = "It has fallen. Raise it again, or leave the gap."
		detail_col.add_child(fell)
	var known := false
	for k in kits:
		if String(k.get("id", "")) == kit_id:
			known = true
	if not known:
		kit_id = ""
		for k in kits:
			if bool(k.get("ok", true)):
				kit_id = String(k.id)
				break
		if kit_id == "":
			kit_id = String(kits[0].get("id", ""))
	detail_col.add_child(_caps("What to build here"))
	var chosen_kit := {}
	for k in kits:
		detail_col.add_child(_kit_row(k))
		if String(k.get("id", "")) == kit_id:
			chosen_kit = k
	order_button = _button("Order", true)
	var ok := not chosen_kit.is_empty() and bool(chosen_kit.get("ok", true))
	order_button.disabled = not ok
	order_button.tooltip_text = "" if ok else String(chosen_kit.get("why", "It cannot be ordered now"))
	order_button.pressed.connect(_on_order.bind(slot_id))
	detail_col.add_child(order_button)
	if not ok and not chosen_kit.is_empty():
		var why := _para(14, host.WARN, 600)
		why.text = String(chosen_kit.get("why", ""))
		detail_col.add_child(why)


func _kit_row(k: Dictionary) -> Control:
	var id := String(k.get("id", ""))
	var chosen := id == kit_id
	var ok := bool(k.get("ok", true))
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = host._flat(Color(host.PANEL, 1.0), 5, Color(host.ACCENT, 0.9) if chosen else host.LINE, false)
	sb.set_border_width_all(2 if chosen else 1)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	slip.add_theme_stylebox_override("panel", sb)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for st in ["hover", "pressed"]:
		var hv := StyleBoxFlat.new()
		hv.bg_color = Color(1, 1, 1, 0.06 if st == "hover" else 0.12)
		hv.set_corner_radius_all(5)
		b.add_theme_stylebox_override(st, hv)
	slip.add_child(b)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 5)
	var inner: VBoxContainer = host._vbox(0)
	inner.add_child(host._label(String(k.get("name", id)), Fonts.cond(700), 16, host.INK if ok else host.INK2))
	var cost := _para(14, host.INK2, 400)
	cost.text = cost_text(k)
	inner.add_child(cost)
	var blurb := String(k.get("blurb", ""))
	if blurb != "":
		var bl := _para(14, host.INK3, 400)
		bl.text = blurb
		inner.add_child(bl)
	if not ok and String(k.get("why", "")) != "":
		var why := _para(14, host.WARN, 600)
		why.text = String(k.why)
		inner.add_child(why)
	pad.add_child(inner)
	slip.add_child(pad)
	b.pressed.connect(choose_kit.bind(id))
	return slip


# ---------------------------------------------------------------------------- doing --

## Picks a slot (from the plan, a row or `focus_on`); picking the one that is picked puts it away.
func select(id: String) -> void:
	if id == selected:
		id = ""
	selected = id
	kit_id = ""
	armed = false
	if String(answer.get("slot", "")) != id:
		answer = {}
	refresh(true)
	_mark_selected()


func choose_kit(id: String) -> void:
	kit_id = id
	refresh(true)


## Orders the chosen kit on the picked slot: `perimeter.order(slot, kit)`; the words are the answer, green when it went through, amber when not.
func order_selected() -> bool:
	var per = _per()
	if per == null or selected == "" or kit_id == "":
		return false
	return _on_order(selected)


func _on_order(slot_id: String) -> bool:
	var per = _per()
	if per == null or not per.has_method("order") or kit_id == "":
		return false
	var ok: bool = bool(per.order(slot_id, kit_id))
	if ok:
		_say(slot_id, "Ordered. The Builders will raise it.", host.OK)
	else:
		var why := "It cannot be ordered now."
		for k in per.kits_for(slot_id) if per.has_method("kits_for") else []:
			if String(k.get("id", "")) == kit_id and String(k.get("why", "")) != "":
				why = String(k.why)
		_say(slot_id, why, host.WARN)
	return ok


func _on_cancel(slot_id: String) -> void:
	var per = _per()
	if per == null or not per.has_method("cancel"):
		return
	var ok: bool = bool(per.cancel(slot_id))
	_say(slot_id, "Order taken back." if ok else "It cannot be cancelled now.", host.OK if ok else host.WARN)


func _on_demolish(slot_id: String) -> void:
	var per = _per()
	if per == null or not per.has_method("demolish"):
		return
	if not armed:
		armed = true
		armed_left = CONFIRM_S
		set_process(true)
		refresh(true)
		return
	armed = false
	var ok: bool = bool(per.demolish(slot_id))
	_say(slot_id, "Taken down. Half the scrap is back." if ok else "It cannot be taken down now.", host.OK if ok else host.WARN)


func _say(slot_id: String, text: String, color: Color) -> void:
	answer = {"slot": slot_id, "text": text, "color": color, "left": ANSWER_S}
	set_process(true)
	refresh(true)


func _process(dt: float) -> void:
	var keep := false
	if armed:
		armed_left -= dt
		if armed_left <= 0.0:
			armed = false
			refresh(true)
		else:
			keep = true
	if not answer.is_empty():
		answer["left"] = float(answer.left) - dt
		if float(answer.left) <= 0.0:
			answer = {}
			refresh(true)
		else:
			keep = true
	if not keep:
		set_process(false)


## A slot's id or its plot's: picks it.
func focus_on(id: String) -> void:
	var s := slot_of(id)
	if s.is_empty():
		return
	if String(s.get("id", "")) != selected:
		select(String(s.get("id", "")))


## (The town has no modal Build page: the panel is the page.)
func full_page() -> void:
	pass


func set_compact(_on: bool) -> void:
	pass


# --------------------------------------------------------------------- the yard's mark --

func _on_hover(id: String) -> void:
	if plan != null and plan.hover_id != id:
		plan.hover_id = id
		plan.queue_redraw()
	_mark(id if id != "" else selected)


func _mark_selected() -> void:
	_mark(selected)


## Marks the slot's plot in the yard (the plot's sign) while the pointer is on it or it is picked; `host.set_build_hover`.
func _mark(slot_id: String) -> void:
	if host == null or not host.has_method("set_build_hover"):
		return
	var plot := ""
	if slot_id != "":
		plot = String(slot_of(slot_id).get("plot", ""))
	if plot == _marked:
		return
	_marked = plot
	host.set_build_hover({"plot": plot} if plot != "" else {})


func _clear_mark() -> void:
	if _marked != "" and host != null and is_instance_valid(host) and host.has_method("set_build_hover"):
		host.set_build_hover({})
	_marked = ""


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh(true)
		_mark_selected()
	else:
		_clear_mark()
