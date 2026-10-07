extends VBoxContainer
## The Build page of the radio panel in the town (One House, WP7): PROJECTS, not places. Fortifying the house is a few clear jobs (the front fence, the gate, a watchtower,
## the side fences, the back fence, the floodlights, planks on the doors, a second tower, reinforcing the fences), each ordered with ONE click. From the top:
##   - THE WHOLE PLAN (scripts/ui/plan_clock.gd): one box over the NEXT card: what everything left costs and how many builder-hours it is, when the builders would be done with it ("Done by
##     15:40 with three builders": they work by day only, so a night between shows as "tomorrow 11:20"), and a chip for the next bell: READY BY DUSK (a check), TIGHT (a clock: only the front and
##     the gate make it), NOT YET (a cross), QUIET NIGHTS: NO RUSH (a moon) before the dead come, with a line saying why ("Add a builder: about 3 hours short."). A card says when it finishes too.
##   - the NEXT card: the project to do now (the first that can be ordered, a fallen section first), with its one button, and under it **Build everything I can afford**
##   - the list of the projects, in the recommended order, finished ones last: each has a name and a picture, what it gives in one line, its price in scrap and builder-hours,
##     about how long it takes with the builders there are, its state (locked and why / ready / building n of m / done) and one button (Build, Cancel)
##   - the plan of the lot (slot_plan.gd): every section, the project under the pointer lit and the rest dimmed
##   - Advanced: every section on its own (build it, cancel it, take it down), shut by default
## A project that the scrap does not pay for in full is ordered as far as it goes, front to back (the builders work the orders in the order they were given); the page says what
## was ordered and what the rest needs. Under the pointer (or picked by a click) a project is marked in the yard with a dashed outline round each of its sections
## (`host.set_build_hover({"project": id})`, scripts/render/perimeter_view.gd); with nothing under the pointer the NEXT project is marked, softly.
##
## What it asks of `sim.perimeter` (scripts/town/perimeter.gd): `projects()` ([{"id", "name", "noun", "button", "icon", "gives", "unit", "state": "locked|ready|building|done", "n",
## "built", "going", "open", "fallen", "scrap", "work", "first_scrap", "can_n", "pay", "time", "builders", "builders_text", "why", "recommended", "progress", "slots"}]),
## `order_project(id)`, `cancel_project(id)`, `order_affordable()`, and for Advanced `slots()`, `kits_for`, `order`, `cancel`, `demolish`. And of the rest, only to draw the plan:
## `sim.base.layout` ("plot", "front", "posts"), `sim.houses.house(id).rect`, `sim.stock.scrap`. A game with no perimeter says "Nothing to build yet".
##
## One of the radio panel's pages: `setup(host, sim_getter, options)`, `refresh()` (each HUD update while it is shown; only what changed is redrawn), `focus_on(id)` (a project's
## id, or a slot's or its plot's: it is picked), `full_page()` (the town has no modal Build page: it does nothing). Every control is FOCUS_NONE: the panel never steals the
## keyboard from the avatar.

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const BuildScreen := preload("res://scripts/ui/build_screen.gd")
const SlotPlan := preload("res://scripts/ui/slot_plan.gd")
const PlanClock := preload("res://scripts/ui/plan_clock.gd")

## The answer to an order stays this many seconds (real time); the second press on Take down must come within CONFIRM_S.
const ANSWER_S := 8.0
const CONFIRM_S := 4.0
const BUTTON_H := 32.0
const EMPTY_UNCLAIMED := "Nothing to build yet. Claim the house, and its projects show here: fences, a gate, a tower, lights."
const EMPTY_CLAIMED := "There is nothing to build round the house yet."
const STATE_WORD := {"locked": "Locked", "open": "Free", "ordered": "Ordered", "building": "Going up", "built": "Built", "broken": "Fallen"}
const PLURAL := {"section": "sections", "door": "doors", "floodlight": "floodlights", "tower": "towers", "part": "parts"}


## The little picture of a project: fence, gate, tower, floodlight, planks, reinforce. Drawn in a box of 32 units, in `tint`.
class ProjectIcon:
	extends Control
	var kind := "fence"
	var tint := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(36, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y) / 32.0
		draw_set_transform(Vector2((size.x - 32.0 * s) * 0.5, (size.y - 32.0 * s) * 0.5), 0.0, Vector2(s, s))
		match kind:
			"gate":
				draw_rect(Rect2(2, 5, 4, 23), tint)
				draw_rect(Rect2(26, 5, 4, 23), tint)
				draw_rect(Rect2(8, 10, 16, 14), tint, false, 2.0)
				draw_line(Vector2(8, 24), Vector2(24, 10), tint, 2.0)
			"tower":
				draw_rect(Rect2(5, 9, 22, 4), tint)
				draw_line(Vector2(8, 13), Vector2(6, 29), tint, 2.5)
				draw_line(Vector2(24, 13), Vector2(26, 29), tint, 2.5)
				draw_line(Vector2(8, 18), Vector2(25, 27), tint, 1.5)
				draw_line(Vector2(24, 18), Vector2(7, 27), tint, 1.5)
				draw_line(Vector2(7, 4), Vector2(7, 9), tint, 2.0)
				draw_line(Vector2(25, 4), Vector2(25, 9), tint, 2.0)
				draw_line(Vector2(7, 5), Vector2(25, 5), tint, 2.0)
			"floodlight":
				draw_line(Vector2(12, 29), Vector2(12, 11), tint, 3.0)
				draw_rect(Rect2(7, 5, 13, 7), tint)
				draw_line(Vector2(22, 9), Vector2(30, 6), tint, 2.0)
				draw_line(Vector2(22, 12), Vector2(30, 14), tint, 2.0)
				draw_line(Vector2(21, 15), Vector2(27, 22), tint, 2.0)
			"planks":
				draw_rect(Rect2(8, 3, 16, 26), tint, false, 2.0)
				for y in [9.0, 16.0, 23.0]:
					draw_line(Vector2(4, y), Vector2(28, y), tint, 3.5)
			"reinforce":
				draw_line(Vector2(2, 20), Vector2(30, 20), tint, 3.0)
				draw_line(Vector2(2, 27), Vector2(30, 27), tint, 3.0)
				for x in [4.0, 13.0, 22.0, 30.0]:
					draw_rect(Rect2(x - 1.5, 16, 3, 15), tint)
				draw_line(Vector2(8, 11), Vector2(16, 3), tint, 2.5)
				draw_line(Vector2(24, 11), Vector2(16, 3), tint, 2.5)
				draw_line(Vector2(16, 3), Vector2(16, 14), tint, 2.5)
			_:
				draw_line(Vector2(2, 13), Vector2(30, 13), tint, 2.5)
				draw_line(Vector2(2, 21), Vector2(30, 21), tint, 2.5)
				for x in [4.0, 12.0, 20.0, 28.0]:
					draw_rect(Rect2(x - 1.5, 7, 3, 20), tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The little mark in the chip of the plan's verdict: a check (ready), a clock (tight), a cross (not yet), a moon (quiet nights): a shape for each, so that the colour is not the only word.
class ChipMark:
	extends Control
	var kind := "calm"
	var tint := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"ok":
				draw_polyline(PackedVector2Array([c + Vector2(-5.5, 0.5), c + Vector2(-1.8, 4.5), c + Vector2(5.5, -4.5)]), tint, 2.4, true)
			"warn":
				draw_arc(c, 6.2, 0.0, TAU, 24, tint, 1.8, true)
				draw_line(c, c + Vector2(0, -4.0), tint, 1.8, true)
				draw_line(c, c + Vector2(3.0, 1.5), tint, 1.8, true)
			"bad":
				draw_line(c + Vector2(-4.5, -4.5), c + Vector2(4.5, 4.5), tint, 2.4, true)
				draw_line(c + Vector2(4.5, -4.5), c + Vector2(-4.5, 4.5), tint, 2.4, true)
			_:
				# a crescent moon: the arc of a circle of 6 from one point where it meets a circle of 5 (a little to the right) to the other, and back along the inside of the smaller one
				var pts := PackedVector2Array()
				for i in 13:
					var a := deg_to_rad(55.3 + (304.7 - 55.3) * float(i) / 12.0)
					pts.append(c + Vector2(cos(a), sin(a)) * 6.0)
				for i in range(1, 12):
					var b := deg_to_rad(279.4 - (279.4 - 80.6) * float(i) / 12.0)
					pts.append(c + Vector2(2.6, 0.0) + Vector2(cos(b), sin(b)) * 5.0)
				draw_colored_polygon(pts, tint)


var host
var sim_getter: Callable
var options := {}
var plan
## The whole plan's summary at the top (scripts/ui/plan_clock.gd): the box, its line, its chip (a mark and words), the reason under it; what it said last, and each project's "finishes 12:10".
var plan_box: PanelContainer
## Shorter than this many pixels (the HUD's height) the NEXT card comes before the summary of the whole plan (`_order_for_height`).
const SHORT_H := 760.0
var _short := false
var plan_line: Label
var plan_chip: PanelContainer
var plan_mark
var plan_chip_label: Label
var plan_reason: Label
var plan_info := {}
var plan_per := {}
var _plan_words_sig := ""
var next_card := {}
var all_button: Button
var answer_label: Label
var empty_label: Label
var list_caption: Label
var plan_caption: Label
var list_box: VBoxContainer
var adv_toggle: Button
var adv_box: VBoxContainer
var stock_label: Label
var people_label: Label
var foot_box: Control
## project id -> the refs of its card in the list (see `_make_card`).
var cards := {}
## The project that is picked (a click on a card or a section of the plan), the one under the pointer on the page, the one the NEXT card is about.
var selected := ""
var card_hover := ""
var next_id := ""
## What the last order, cancel or take-down said: {"text", "color", "left"}; {} when nothing is up.
var answer := {}
## Advanced: slot id -> {"slot", "button", "state"} for the rows; the slot whose Take down is armed, and for how long.
var adv_rows := {}
var armed_slot := ""
var armed_left := 0.0
var _adv_sig := ""
var _plan_sig := ""
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


## The projects now, or [] in a game that has no perimeter.
func projects() -> Array:
	var per = _per()
	if per == null or not per.has_method("projects"):
		return []
	var got = per.projects()
	return got if got is Array else []


func slots() -> Array:
	var per = _per()
	if per == null or not per.has_method("slots"):
		return []
	var got = per.slots()
	return got if got is Array else []


func project_of(id: String) -> Dictionary:
	for p in projects():
		if String(p.get("id", "")) == id:
			return p
	return {}


## Whether the house has been claimed (the page says what to do first when it has not).
func _claimed() -> bool:
	var s = _sim()
	var b = s.get("base") if s != null else null
	return b != null and b.get("claimed") == true


# ------------------------------------------------------------------------- build --

func _build() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label = _para(14, host.INK2, 400)
	empty_label.text = EMPTY_UNCLAIMED
	empty_label.visible = false
	add_child(empty_label)
	# the whole plan: what it costs, when the builders would be done, and whether that is before the bell
	_build_plan_box()
	# the NEXT card and the one-click buttons
	next_card = _make_card(true)
	add_child(next_card.panel)
	all_button = _button("Build everything I can afford")
	all_button.tooltip_text = "Orders every project the scrap pays for, in this order: the next one first"
	all_button.pressed.connect(_on_all)
	add_child(all_button)
	answer_label = _para(14, host.INK, 600)
	answer_label.visible = false
	add_child(answer_label)
	list_caption = _caps("Projects")
	add_child(list_caption)
	list_box = host._vbox(5)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(list_box)
	plan_caption = _caps("The plan")
	add_child(plan_caption)
	plan = SlotPlan.new()
	plan.setup(host)
	plan.picked.connect(_on_pick)
	plan.hovered.connect(_on_plan_hover)
	add_child(plan)
	adv_toggle = _button("Advanced: every section on its own")
	adv_toggle.pressed.connect(_on_adv_toggle)
	add_child(adv_toggle)
	adv_box = host._vbox(3)
	adv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adv_box.visible = false
	add_child(adv_box)
	_build_foot()


## The summary of the whole plan, above the NEXT card: one line (the price, the builder-hours, when the builders are done), the verdict chip and the reason. It is made once and filled by
## `_apply_plan`; it is hidden when there is nothing to say.
func _build_plan_box() -> void:
	plan_box = PanelContainer.new()
	plan_box.mouse_filter = Control.MOUSE_FILTER_PASS
	plan_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = host._flat(Color(host.PANEL, 1.0), 6, host.LINE2, false)
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	plan_box.add_theme_stylebox_override("panel", sb)
	var col: VBoxContainer = host._vbox(4)
	var head: HBoxContainer = host._hbox(8)
	head.add_child(_caps("The whole plan"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	plan_chip = PanelContainer.new()
	plan_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	plan_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	var cs := StyleBoxFlat.new()
	cs.set_corner_radius_all(4)
	cs.set_border_width_all(1)
	cs.content_margin_left = 8
	cs.content_margin_right = 9
	cs.content_margin_top = 3
	cs.content_margin_bottom = 3
	plan_chip.add_theme_stylebox_override("panel", cs)
	var chip_row: HBoxContainer = host._hbox(6)
	plan_mark = ChipMark.new()
	chip_row.add_child(plan_mark)
	plan_chip_label = host._label("", Fonts.cond(700, 1), 15, host.INK)
	chip_row.add_child(plan_chip_label)
	plan_chip.add_child(chip_row)
	head.add_child(plan_chip)
	col.add_child(head)
	plan_line = _para(15, host.INK, 600)
	col.add_child(plan_line)
	plan_reason = _para(14, host.INK2, 400)
	col.add_child(plan_reason)
	plan_box.add_child(col)
	plan_box.visible = false
	add_child(plan_box)


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
		b.custom_minimum_size = Vector2(0, BUTTON_H + 4.0)
		b.add_theme_font_size_override("font_size", 16)
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
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = host.LINE2
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(rule)
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
	people_label.tooltip_text = "The people in the house, you included: more of them open more projects"
	people_label.mouse_filter = Control.MOUSE_FILTER_PASS
	counts.add_child(people_label)
	foot.add_child(counts)
	foot_box = foot
	add_child(foot)


## One project's card: the picture, the name and the state, what it gives, what it costs, how long it takes, why it cannot be ordered, the buttons. `big` is the NEXT card (a gold
## edge, a caption over the name, the full words on its button). Made once; `_apply_card` brings it up to date, so that a button is never swapped under the pointer.
func _make_card(big: bool) -> Dictionary:
	var c := {"id": "", "sig": "", "big": big}
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = host._flat(Color(host.PANEL_HI, 1.0), 6, Color(host.ACCENT, 0.9) if big else host.LINE2, false)
	sb.set_border_width_all(2 if big else 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8 if not big else 9
	sb.content_margin_bottom = 9 if not big else 10
	panel.add_theme_stylebox_override("panel", sb)
	var row: HBoxContainer = host._hbox(10)
	var icon := ProjectIcon.new()
	icon.custom_minimum_size = Vector2(46, 46) if big else Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var col: VBoxContainer = host._vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = host._hbox(8)
	if big:
		var cap: Label = host._label("NEXT", Fonts.cond(700, 1), 14, host.ACCENT)
		c["caption"] = cap
		head.add_child(cap)
	var name_l: Label = host._label("", Fonts.cond(700), 20 if big else 17, host.INK)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_l)
	var chip: Label = host._label("", Fonts.cond(700, 1), 14, host.INK3)
	head.add_child(chip)
	col.add_child(head)
	var gives := _para(14, host.INK2, 400)
	col.add_child(gives)
	var stats := _para(14, host.INK, 600)
	col.add_child(stats)
	var time := _para(14, host.INK3, 400)
	col.add_child(time)
	var meter = BuildScreen.Meter.new()
	meter.custom_minimum_size = Vector2(40, 6)
	meter.track = Color(host.INK, 0.16)
	meter.fill = host.WARN
	col.add_child(meter)
	var why := _para(14, host.WARN, 600)
	col.add_child(why)
	var actions: HBoxContainer = host._hbox(8)
	var action := _button("Build", big)
	if big:
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel := _button("Cancel")
	actions.add_child(action)
	actions.add_child(cancel)
	col.add_child(actions)
	row.add_child(col)
	panel.add_child(row)
	panel.gui_input.connect(_on_card_input.bind(c))
	c["panel"] = panel
	c["icon"] = icon
	c["name"] = name_l
	c["chip"] = chip
	c["gives"] = gives
	c["stats"] = stats
	c["time"] = time
	c["meter"] = meter
	c["why"] = why
	c["action"] = action
	c["cancel"] = cancel
	c["style"] = sb
	action.pressed.connect(_on_build_pressed.bind(c))
	cancel.pressed.connect(_on_cancel_pressed.bind(c))
	return c


# ------------------------------------------------------------------------ the words --

static func _num(x: float) -> String:
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x


static func plural(unit: String, n: int) -> String:
	return unit if n == 1 else String(PLURAL.get(unit, unit + "s"))


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


## The state chip of a project: its word and colour.
func chip_of(p: Dictionary) -> Array:
	var state := String(p.get("state", "ready"))
	match state:
		"locked":
			return ["LOCKED", host.INK3]
		"building":
			return ["BUILDING %d OF %d" % [int(p.built), int(p.n)], host.WARN]
		"done":
			return ["DONE", host.OK]
	if int(p.get("fallen", 0)) > 0:
		return ["%d FALLEN" % int(p.fallen), host.DANGER_TEXT]
	if int(p.get("built", 0)) > 0:
		return ["%d OF %d UP" % [int(p.built), int(p.n)], host.ACCENT]
	return ["READY", host.ACCENT]


## What the price line of a project says: "5 sections, 21 scrap, 13 builder-hours".
func stats_of(p: Dictionary) -> String:
	var open := int(p.get("open", 0))
	var parts: Array = ["%d %s" % [open, plural(String(p.get("unit", "part")), open)]] if open > 1 else []
	parts.append("%d scrap" % int(p.scrap))
	parts.append("%s builder-hours" % _num(float(p.work)))
	return ", ".join(parts)


## "about a minute and a half", for minutes of standing at the fence after E.
static func hands_text(minutes: float) -> String:
	if minutes < 0.75:
		return "under a minute"
	if minutes < 1.25:
		return "about a minute"
	if minutes < 1.75:
		return "about a minute and a half"
	return "about %d minutes" % roundi(minutes)


## The line under a project's price: how long it takes (with how many builders), or that there is nobody to build it.
func time_of(p: Dictionary) -> String:
	var state := String(p.get("state", "ready"))
	if state != "ready" and state != "building":
		return ""
	if int(p.get("builders", 0)) <= 0:
		# (EARLY: her own hands build: stand at the fence, press E once and stay by it)
		var mins := float(p.get("hands_minutes", 0.0))
		if state == "ready":
			return "Nobody else is here to build it: press E at the fence and stay by it, %s" % hands_text(mins) if mins > 0.0 else "Nobody else is here to build it: press E at the fence and stay by it"
		return "Waiting for hands: stand at the fence, press E and stay by it"
	var t := String(p.get("time", ""))
	if t == "":
		return ""
	var line := ("Takes %s with %s" if state == "ready" else "Done in %s with %s") % [t, String(p.builders_text)]
	# (the clock time: ordered now, behind what is already going up, and the night between when the work spills over it: scripts/ui/plan_clock.gd)
	var fin := String(plan_per.get(String(p.get("id", "")), ""))
	if fin != "":
		return "%s. %s." % [line, fin.substr(0, 1).to_upper() + fin.substr(1)]
	return line + (", so into tomorrow" if bool(p.get("spills", false)) else "")


## Brings the whole plan's summary up to date: the line, the verdict chip and its reason; and `plan_per`, each project's "finishes 12:10" for the cards.
func _apply_plan(infos: Array) -> void:
	plan_info = PlanClock.assess(infos, PlanClock.context(_sim()))
	plan_per = plan_info.per
	var line := String(plan_info.line)
	var chip := String(plan_info.chip)
	var reason := String(plan_info.reason)
	var tone := String(plan_info.tone)
	plan_box.visible = line != ""
	var sig := "%s|%s|%s|%s" % [line, chip, reason, tone]
	if sig == _plan_words_sig:
		return
	_plan_words_sig = sig
	plan_line.text = String(plan_info.summary)
	var tint: Color = {"ok": host.OK, "warn": host.WARN, "bad": host.DANGER_TEXT}.get(tone, host.INK2)
	plan_chip.visible = chip != ""
	plan_chip_label.text = chip
	plan_chip_label.add_theme_color_override("font_color", tint)
	plan_mark.kind = tone
	plan_mark.tint = tint
	plan_mark.queue_redraw()
	var cs: StyleBoxFlat = plan_chip.get_theme_stylebox("panel")
	cs.bg_color = Color(tint, 0.16)
	cs.border_color = Color(tint, 0.75)
	plan_reason.text = reason
	plan_reason.visible = reason != ""
	plan_chip.tooltip_text = "READY BY DUSK: the house is up before the bell, and the scrap is there. TIGHT: only the front and the gate. NOT YET: not even those."


## What the button of a project says (`big`: the NEXT card's, with the whole of the job in it): "Build", "Build the front fence", "Rebuild", "Reinforce the fences", "Start with 2 of 5".
func action_text(p: Dictionary, big: bool) -> String:
	var open := int(p.get("open", 0))
	var can_n := int(p.get("can_n", 0))
	var fallen := int(p.get("fallen", 0))
	if can_n > 0 and can_n < open:
		return "Build %d of %d %s" % [can_n, open, plural(String(p.get("unit", "part")), open)]
	if fallen > 0 and fallen >= open:
		return ("Rebuild %s" % String(p.noun)) if big else "Rebuild"
	if big:
		return String(p.button)
	return "Reinforce" if String(p.get("icon", "")) == "reinforce" else "Build"


## The small line under the button: what a part payment pays for, or what is missing.
func missing_of(p: Dictionary) -> String:
	if String(p.get("state", "")) != "ready":
		return ""
	var open := int(p.get("open", 0))
	var can_n := int(p.get("can_n", 0))
	var unit := String(p.get("unit", "part"))
	if can_n == 0:
		var all := int(p.scrap)
		var first := int(p.first_scrap)
		return ("%s to start." % String(p.why) + ((" All of it is %d." % all) if open > 1 else "")) if first > 0 else String(p.why)
	if can_n < open:
		return "The scrap pays for %d of %d %s. The rest needs %d more." % [can_n, open, plural(unit, open), maxi(1, int(p.scrap) - _scrap_now())]
	return ""


func _scrap_now() -> int:
	var s = _sim()
	return int(float(s.stock.scrap)) if s != null and s.get("stock") != null else 0


# ----------------------------------------------------------------------- the sim -> the page --

## Brings the page up to date; without `force` only what changed is touched.
## In a window shorter than SHORT_H the panel has room for little more than one card: the NEXT card and its button come first, and the summary of the whole plan under them, so that the first
## thing to do (Build the front fence) is on the page without a scroll. In a taller one the summary stays over the NEXT card, as the page was drawn.
func _order_for_height() -> void:
	var short: bool = host != null and float(host.size.y) > 0.0 and float(host.size.y) < SHORT_H
	if short == _short:
		return
	_short = short
	if short:
		move_child(plan_box, answer_label.get_index())    # (after the answer's line, which is under the one-click button)
	else:
		move_child(plan_box, empty_label.get_index() + 1)


func refresh(force: bool = false) -> void:
	if host == null or not _built:
		return
	var infos: Array = projects()
	var any := not infos.is_empty()
	_tick_labels()
	_order_for_height()
	empty_label.text = EMPTY_CLAIMED if _claimed() else EMPTY_UNCLAIMED
	empty_label.visible = not any
	for n in [next_card.panel, all_button, plan_caption, plan, list_caption, adv_toggle, foot_box]:
		if (n as Control).visible != any:
			(n as Control).visible = any
	if not any:
		adv_box.visible = false
		plan_box.visible = false
		return
	_sync_cards(infos)
	_apply_plan(infos)
	next_id = ""
	for p in infos:
		if bool(p.get("recommended", false)):
			next_id = String(p.id)
	_apply_next(infos)
	var can_any := false
	for p in infos:
		if String(p.state) == "ready" and int(p.can_n) > 0:
			can_any = true
	all_button.disabled = not can_any
	for id in cards:
		var c: Dictionary = cards[id]
		var info := _info(infos, String(id))
		if not info.is_empty():
			_apply_card(c, info, force)
	_fill_plan(infos)
	if adv_box.visible:
		_sync_adv()
	_sync_mark()


func _info(infos: Array, id: String) -> Dictionary:
	for p in infos:
		if String(p.id) == id:
			return p
	return {}


## The cards of the list are made for the projects there are (once) and put in order: not finished first, in the recommended order; finished ones after.
func _sync_cards(infos: Array) -> void:
	var have := {}
	for p in infos:
		have[String(p.id)] = true
	for id in cards.keys():
		if not have.has(id):
			var gone: Dictionary = cards[id]
			list_box.remove_child(gone.panel)
			gone.panel.queue_free()
			cards.erase(id)
	for p in infos:
		if not cards.has(String(p.id)):
			var c := _make_card(false)
			c["id"] = String(p.id)
			cards[String(p.id)] = c
			list_box.add_child(c.panel)
	var at := 0
	for pass_n in 2:
		for p in infos:
			var done := String(p.state) == "done"
			if (pass_n == 0) == (not done):
				var node: Control = cards[String(p.id)].panel
				if node.get_index() != at:
					list_box.move_child(node, at)
				at += 1


## Fills a card from a project (only when something it shows changed, or `force`).
func _apply_card(c: Dictionary, p: Dictionary, force: bool = false) -> void:
	var big: bool = bool(c.big)
	var sig := "%s|%s|%d|%d|%d|%d|%d|%d|%s|%d|%s|%d|%d|%s|%s" % [String(p.id), String(p.state), int(p.built), int(p.going), int(p.open), int(p.can_n), int(p.scrap), int(p.fallen), String(p.time),
		roundi(float(p.progress) * 50.0), String(p.why), int(p.builders), crew_now(), str(p.get("spills", false)), String(plan_per.get(String(p.id), ""))]
	if not force and sig == String(c.sig):
		return
	c.sig = sig
	c.id = String(p.id)
	var state := String(p.state)
	c.icon.kind = String(p.icon)
	c.icon.tint = host.OK if state == "done" else (host.ACCENT if big else host.INK2) if state != "locked" else Color(host.INK3, 0.8)
	c.icon.queue_redraw()
	c.name.text = String(p.name)
	c.name.add_theme_color_override("font_color", host.INK if state != "locked" else host.INK2)
	var chip: Array = chip_of(p)
	c.chip.text = String(chip[0])
	c.chip.add_theme_color_override("font_color", chip[1])
	var done := state == "done"
	c.gives.text = String(p.gives)
	c.gives.visible = not done or big
	c.gives.add_theme_color_override("font_color", host.INK2 if state != "locked" else host.INK3)
	var money := state == "ready" or state == "building"
	if state == "building":
		c.stats.text = "%d of %d %s up" % [int(p.built), int(p.n), plural(String(p.unit), int(p.n))]
	else:
		c.stats.text = stats_of(p) if money else ""
	c.stats.visible = money and String(c.stats.text) != ""
	var time_line := time_of(p)
	c.time.text = time_line
	c.time.visible = time_line != ""
	c.meter.visible = state == "building"
	c.meter.value = float(p.progress)
	c.meter.queue_redraw()
	var line := ""
	var warn := true
	match state:
		"locked":
			line = String(p.why)
		"ready":
			line = missing_of(p)
			warn = int(p.can_n) == 0
	c.why.text = line
	c.why.visible = line != ""
	c.why.add_theme_color_override("font_color", host.WARN if warn else host.INK3)
	var ready := state == "ready"
	c.action.visible = ready
	c.action.text = action_text(p, big)
	c.action.disabled = int(p.can_n) <= 0
	c.action.tooltip_text = String(p.why) if int(p.can_n) <= 0 else ""
	c.cancel.visible = state == "building"
	c.cancel.tooltip_text = "Take the order back: the scrap comes back (half of it where work had begun)"
	var sb: StyleBoxFlat = c.style
	if not big:
		var picked := String(p.id) == selected
		sb.border_color = Color(host.ACCENT, 0.85) if picked else host.LINE2
		sb.set_border_width_all(2 if picked else 1)
		sb.bg_color = Color(host.PANEL_HI, 1.0) if state != "done" else Color(host.PANEL, 1.0)


## The NEXT card: the recommended project, or what to say when there is none.
func _apply_next(infos: Array) -> void:
	var c := next_card
	if next_id != "":
		var p := _info(infos, next_id)
		c.caption.text = "NEXT: REBUILD" if int(p.fallen) > 0 else "NEXT"
		_apply_card(c, p, false)
		c.panel.visible = true
		return
	# nothing can be ordered: say why, and what opens next
	var going := 0
	var waiting: Array = []
	var locked_at := 99
	var locked_name := ""
	for p in infos:
		match String(p.state):
			"building":
				going += 1
			"locked":
				if int(p.need_crew) < locked_at and int(p.need_crew) > crew_now():
					locked_at = int(p.need_crew)
					locked_name = String(p.name).to_lower()
				waiting.append(p)
	var sig := "none|%d|%d|%s" % [going, locked_at, locked_name]
	if String(c.sig) == sig:
		return
	c.sig = sig
	c.caption.text = "ALL SET" if going == 0 and waiting.is_empty() else "NOTHING TO ORDER"
	c.icon.kind = "fence"
	c.icon.tint = host.OK if going == 0 and waiting.is_empty() else host.INK2
	c.icon.queue_redraw()
	if going > 0:
		c.name.text = "It is all going up"
		c.gives.text = "The builders are on it. Orders you give wait their turn."
	elif waiting.is_empty():
		c.name.text = "The house is as strong as it gets"
		c.gives.text = "Everything is built. Mend what the dead break."
	else:
		c.name.text = "Nothing more to order yet"
		c.gives.text = ("More opens when %d people are here: %s." % [locked_at, locked_name]) if locked_at < 99 else "More opens when more people are here."
	c.chip.text = ""
	c.gives.visible = true
	c.gives.add_theme_color_override("font_color", host.INK2)
	for k in ["stats", "time", "why", "meter", "action", "cancel"]:
		(c[k] as Control).visible = false


func _tick_labels() -> void:
	var sim = _sim()
	if sim != null and sim.get("stock") != null:
		stock_label.text = "%d scrap" % roundi(float(sim.stock.scrap))
	people_label.text = "%d in the house" % crew_now()


func _fill_plan(infos: Array) -> void:
	var sim = _sim()
	var base = sim.get("base") if sim != null else null
	var layout: Dictionary = base.layout if base != null and base.get("layout") is Dictionary else {}
	var house_rect = null
	var houses = sim.get("houses") if sim != null else null
	if base != null and houses != null and houses.has_method("house") and base.get("house") != null and int(base.house) >= 0:
		var hh = houses.house(int(base.house))
		if hh is Dictionary:
			house_rect = hh.get("rect")
	var names := {}
	for p in infos:
		names[String(p.id)] = String(p.name)
	var list: Array = []
	var sig := "%s" % [str(selected)]
	for s in slots():
		var d: Dictionary = (s as Dictionary).duplicate()
		d["project_name"] = String(names.get(String(d.get("project", "")), ""))
		list.append(d)
		sig += "|%s,%s,%s" % [String(d.get("id", "")), String(d.get("state", "")), String(d.get("project", ""))]
	plan.selected_project = selected
	if sig == _plan_sig:
		return
	_plan_sig = sig
	var posts: Array = []
	for p in layout.get("posts", []):
		if p is Dictionary and p.get("pos") is Array and (p.pos as Array).size() >= 2:
			posts.append(Vector2(float(p.pos[0]) + 0.5, float(p.pos[1]) + 0.5))
	plan.set_data({"lot": layout.get("plot"), "house": house_rect, "front": String(layout.get("front", "S")), "slots": list, "posts": posts})


# ---------------------------------------------------------------------------- doing --

func _on_build_pressed(c: Dictionary) -> void:
	var id := String(c.id)
	if id != "":
		order_project(id)


## Orders a project (`perimeter.order_project`); the words are the answer, green when something went through, amber when not.
func order_project(id: String) -> Dictionary:
	var per = _per()
	if per == null or not per.has_method("order_project"):
		return {}
	var r: Dictionary = per.order_project(id)
	_say(String(r.get("line", "")), host.OK if bool(r.get("ok", false)) else host.WARN)
	return r


func _on_cancel_pressed(c: Dictionary) -> void:
	var id := String(c.id)
	var per = _per()
	if id == "" or per == null or not per.has_method("cancel_project"):
		return
	var r: Dictionary = per.cancel_project(id)
	_say(String(r.get("line", "")), host.OK if bool(r.get("ok", false)) else host.WARN)


func _on_all() -> void:
	order_everything()


func order_everything() -> Dictionary:
	var per = _per()
	if per == null or not per.has_method("order_affordable"):
		return {}
	var r: Dictionary = per.order_affordable()
	_say(String(r.get("line", "")), host.OK if bool(r.get("ok", false)) else host.WARN)
	return r


## A click on a card (not on its buttons) picks the project (it stays marked in the yard); on the one that is picked, puts it away.
func _on_card_input(ev: InputEvent, c: Dictionary) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		select(String(c.id))


func _on_pick(project_id: String) -> void:
	select(project_id)


func _on_plan_hover(_project_id: String) -> void:
	_sync_mark()


## Picks a project (from a card, the plan or `focus_on`); picking the one that is picked puts it away.
func select(id: String) -> void:
	selected = "" if id == selected else id
	refresh(true)
	_sync_mark()


func _say(text: String, color: Color) -> void:
	answer = {"text": text, "color": color, "left": ANSWER_S}
	answer_label.text = text
	answer_label.add_theme_color_override("font_color", color)
	answer_label.visible = text != ""
	set_process(true)
	refresh(true)


func _process(dt: float) -> void:
	if not answer.is_empty():
		answer["left"] = float(answer.left) - dt
		if float(answer.left) <= 0.0:
			answer = {}
			answer_label.visible = false
	if armed_slot != "":
		armed_left -= dt
		if armed_left <= 0.0:
			armed_slot = ""
			_adv_sig = ""
			_sync_adv()
	_poll_hover()


## Which card the pointer is on (a card the scroll has hidden is not): its project is lit on the plan and marked in the yard.
func _poll_hover() -> void:
	if not is_visible_in_tree():
		return
	var m := get_global_mouse_position()
	var found := ""
	var view := get_parent() as Control
	if view == null or view.get_global_rect().has_point(m):
		if next_card.panel.visible and next_id != "" and (next_card.panel as Control).get_global_rect().has_point(m):
			found = next_id
		else:
			for id in cards:
				var node: Control = cards[id].panel
				if node.visible and node.get_global_rect().has_point(m):
					found = String(id)
					break
	if found != card_hover:
		card_hover = found
		if plan != null:
			plan.card_hover = found
			plan.queue_redraw()
		_sync_mark()


## A project's id, or a slot's or its plot's: picks it.
func focus_on(id: String) -> void:
	var want := ""
	if not project_of(id).is_empty():
		want = id
	else:
		for s in slots():
			if String(s.get("id", "")) == id or (String(s.get("plot", "")) == id and id != ""):
				want = String(s.get("project", ""))
	if want != "" and want != selected:
		select(want)


## (The town has no modal Build page: the panel is the page.)
func full_page() -> void:
	pass


func set_compact(_on: bool) -> void:
	pass


# --------------------------------------------------------------------- the yard's mark --

## The project the yard marks: the one under the pointer (the plan's, else a card's), else the one that is picked, else (softly) the NEXT one.
func marked_project() -> Array:
	var id := ""
	if plan != null and plan.hover_project != "":
		id = plan.hover_project
	elif card_hover != "":
		id = card_hover
	elif selected != "":
		id = selected
	if id != "":
		return [id, false]
	return [next_id, true] if next_id != "" else ["", false]


func _sync_mark() -> void:
	if host == null or not host.has_method("set_build_hover"):
		return
	var m := marked_project()
	var key := "%s|%s" % [m[0], str(m[1])]
	if key == _marked:
		return
	_marked = key
	host.set_build_hover({"project": String(m[0]), "soft": bool(m[1])} if String(m[0]) != "" else {})


func _clear_mark() -> void:
	if _marked != "" and host != null and is_instance_valid(host) and host.has_method("set_build_hover"):
		host.set_build_hover({})
	_marked = ""


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		set_process(true)
		refresh(true)
	else:
		set_process(not answer.is_empty() or armed_slot != "")
		card_hover = ""
		if plan != null:
			plan.card_hover = ""
		_clear_mark()


# ----------------------------------------------------------------------- Advanced --

## Opens the Advanced fold (a screenshot's `--radio=build,advanced`).
func open_advanced() -> void:
	if not adv_box.visible:
		_on_adv_toggle()


func _on_adv_toggle() -> void:
	adv_box.visible = not adv_box.visible
	adv_toggle.text = "Advanced: hide the sections" if adv_box.visible else "Advanced: every section on its own"
	_adv_sig = ""
	if adv_box.visible:
		_sync_adv()


func _sync_adv() -> void:
	var list := slots()
	var sig := armed_slot
	for s in list:
		sig += "|%s,%s,%s,%s" % [String(s.get("id", "")), String(s.get("state", "")), String(s.get("kit", "")), String(s.get("up", ""))]
	if sig == _adv_sig:
		return
	_adv_sig = sig
	for c in adv_box.get_children():
		adv_box.remove_child(c)
		c.queue_free()
	adv_rows.clear()
	adv_box.add_child(_para_note("Each section on its own, with the plainest kit. A project orders them all at once."))
	for s in list:
		adv_box.add_child(_adv_row(s))


func _para_note(text: String) -> Label:
	var l := _para(14, host.INK3, 400)
	l.text = text
	return l


func _adv_row(s: Dictionary) -> Control:
	var id := String(s.get("id", ""))
	var state := String(s.get("state", "open"))
	var row: HBoxContainer = host._hbox(8)
	var name_l: Label = host._label(String(s.get("name", "Place")), Fonts.cond(600), 15, host.INK)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_l)
	var word := String(STATE_WORD.get(state, state))
	if state == "built" and String(s.get("kit_name", "")) != "":
		word = String(s.kit_name)
	if String(s.get("up", "")) != "":
		word = "Reinforcing"
	var chip: Label = host._label(word, Fonts.cond(700, 1), 14, SlotPlan.STATE_COLOR.get(state, host.INK3))
	row.add_child(chip)
	var b: Button = null
	match state:
		"open", "broken":
			b = _button("Rebuild" if state == "broken" else "Build")
			b.pressed.connect(_on_adv_build.bind(id))
		"ordered", "building":
			b = _button("Cancel")
			b.pressed.connect(_on_adv_cancel.bind(id))
		"built":
			if String(s.get("up", "")) != "":
				b = _button("Cancel")
				b.pressed.connect(_on_adv_cancel.bind(id))
			else:
				b = _button("Press again" if armed_slot == id else "Take down")
				b.tooltip_text = "Takes it down: half the scrap comes back"
				b.pressed.connect(_on_adv_demolish.bind(id))
		_:
			chip.tooltip_text = String(s.get("why_not", ""))
	if b != null:
		b.custom_minimum_size.x = 92
		row.add_child(b)
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(92, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
	adv_rows[id] = {"slot": s, "row": row}
	return row


func _on_adv_build(id: String) -> void:
	var per = _per()
	if per == null:
		return
	var pick := ""
	var why := "It cannot be ordered now."
	for k in per.kits_for(id):
		if bool(k.get("ok", false)):
			pick = String(k.id)
			break
		why = String(k.get("why", why))
	if pick != "" and bool(per.order(id, pick)):
		_say("Ordered. The builders will raise it.", host.OK)
	else:
		_say(why, host.WARN)


func _on_adv_cancel(id: String) -> void:
	var per = _per()
	if per == null:
		return
	var ok: bool = bool(per.cancel(id))
	_say("Order taken back." if ok else "It cannot be cancelled now.", host.OK if ok else host.WARN)


func _on_adv_demolish(id: String) -> void:
	var per = _per()
	if per == null:
		return
	if armed_slot != id:
		armed_slot = id
		armed_left = CONFIRM_S
		set_process(true)
		_adv_sig = ""
		_sync_adv()
		return
	armed_slot = ""
	var ok: bool = bool(per.demolish(id))
	_say("Taken down. Half the scrap is back." if ok else "It cannot be taken down now.", host.OK if ok else host.WARN)
