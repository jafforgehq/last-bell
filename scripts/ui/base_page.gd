## The Base page of the radio panel (round 25, V25.1): where the player RUNS the base rather than staffs it. Top to bottom:
##
##   Today        what the base is worried about, ranked (`briefing.concerns()`: an icon, the words in the colour of the level, what is under them and a
##                small button to the page that handles it: `host.open_radio(page, {"focus": id})`), and the last evening's debrief (what got done, what
##                slipped: the latest "debrief" of the News).
##   Priorities   six chips (Food, Water, Defence, Rebuilding, Rest, Scavenging) that rank up to four in the order they are tapped (`priorities.toggle`);
##                under them what the base will do today (`priorities.seat_plan()`: "garden 2, bench 1, builders 1"), what the priorities add to the wall
##                line and the bench's target ("Wall line 70% + 15 = 85%"), who the player moved by hand and the base will not move back ("Pinned by you:
##                Dez (Workbench)", with **Let the base decide**), and, while nothing is ranked, the suggestion with **Use these**.
##   Policies     the four dials (policy_dials.gd): the option that is set filled, its costs and gains under it, the sim's reason when a change is refused.
##   Facilities   a dot and a line for each station: what it waits on ("Workshop: waiting on scrap", `briefing.facilities()`), with a button to the page
##                that fixes it; the ones that are working are folded away.
##   Trouble      the open problems (problem_list.gd, when there is such a view), each with its time, Go there and Ask.
##   the foot     Jobs (advanced), Build.
##
## The page asks the sim and says what it answers: every number, line and refusal is the modules' (`briefing`, `priorities`, `policies`, `problems`), and every
## read is guarded (`has_method`): an older fake has none and the section says so, no error. It never pauses the game and takes no key (every control is
## FOCUS_NONE: W A S D and E keep walking and using); a control that is off has the reason as its tooltip.
##
## The radio panel (radio_panel.gd) gives every page the same four functions: `setup(host, sim_getter, options)`, `refresh()` (each HUD update while it is
## open: cheap, a part is redrawn only when what it shows changed), `focus_on(id)` (a priority id or "priorities" for the chips, a dial id or "policies" for
## the dials, a facility id, "problems", "today") and `full_page()` (the Jobs screen, the modal Duty roster).
extends VBoxContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const PriorityKit := preload("res://scripts/ui/priority_kit.gd")
const PolicyDials := preload("res://scripts/ui/policy_dials.gd")

const PROBLEM_LIST_PATH := "res://scripts/ui/problem_list.gd"
## How long a section stays lit after `focus_on`, and how long the answer to a tap stays under the chips (seconds).
const FOCUS_S := 4.0
const ANSWER_S := 6.0
## The concerns are asked of the sim this often at most (real seconds): `refresh_now` asks at once.
const CONCERN_EVERY_S := 0.5
const MAX_CONCERNS := 8
## What the pages are called on a button.
const PAGE_WORDS := {"jobs": "Jobs", "build": "Build", "map": "Map", "news": "News", "base": "Base"}
## The words for a station in "what the base will do today", by its id (the station's own name for one that is not here).
const STATION_WORDS := {"bench": "bench", "builders": "builders", "garden": "garden", "watch": "lookout", "infirmary": "infirmary", "radio": "radio desk", "salvage": "salvage"}
const SLIP_BG := Color("#22362f")
const SLIP_EDGE := Color(0.93, 0.96, 0.89, 0.16)
const NO_BRIEFING := "The briefing is not in this game"

var host
var sim_getter: Callable
var options := {}
## The priority chips by id (priority_kit.gd) and the dials (policy_dials.gd).
var chips := {}
var dials
## Today: the rows of the concerns ({"id", "row", "label", "button", "page", "focus"}), the debrief's lines and the tally under the chips.
var today_rows: Array = []
var debrief_labels: Array = []
var plan_label: Label
var shift_label: Label
var answer_label: Label
var suggest_row: HBoxContainer
var suggest_label: Label
var use_button: Button
var pins_row: HBoxContainer
var pins_label: Label
var release_button: Button
## The facilities by id: {"row", "dot", "label", "button", "ok"}; the fold of the ones that are working.
var facility_rows := {}
var ok_toggle: Button
## The Trouble list of problem_list.gd (null when there is no such view), and the foot's buttons.
var trouble_list
var jobs_button: Button
var build_button: Button
## Section id -> its title label, and its box: "today", "priorities", "policies", "facilities", "trouble".
var titles := {}
var sections := {}

var _built := false
var _compact := false
var _today_box: VBoxContainer
var _debrief_box: VBoxContainer
var _fac_box: VBoxContainer
var _fac_ok_box: VBoxContainer
var _trouble_box: VBoxContainer
var _trouble_empty: Label
var _concerns: Array = []
var _concerns_at := -1000000
var _today_sig := ""
var _debrief_sig := ""
var _plan_sig := ""
var _fac_sig := ""
var _show_ok := false
var _answer := {}
var _focus := {}
var _focus_until := 0
var _skipped := 0


func setup(p_host, p_sim_getter: Callable, p_options: Dictionary = {}) -> void:
	host = p_host
	sim_getter = p_sim_getter
	options = p_options
	if _built:
		refresh()
		return
	_built = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_build()
	refresh_now()


func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _mod(name: String):
	var s = _sim()
	return s.get(name) if s != null else null


func _now() -> int:
	return Time.get_ticks_msec() + _skipped


## Moves the page's clock on (tests: the answers' and the focus' time).
func skip_ahead(ms: int) -> void:
	_skipped += ms


func set_compact(on: bool) -> void:
	_compact = on
	if trouble_list != null and trouble_list.has_method("set_compact"):
		trouble_list.set_compact(on)


# ------------------------------------------------------------------------ build --

func _build() -> void:
	# Today
	var today := _section("today", "Today")
	_today_box = host._vbox(5)
	today.add_child(_today_box)
	_debrief_box = host._vbox(2)
	today.add_child(_debrief_box)
	# Priorities
	var prio := _section("priorities", "Priorities")
	var made := PriorityKit.make(host, _on_chip)
	chips = made.chips
	prio.add_child(made.flow)
	answer_label = _para("", 12, host.WARN, 600)
	answer_label.visible = false
	prio.add_child(answer_label)
	suggest_row = host._hbox(8)
	suggest_label = _para("", 12, host.INK2, 600)
	suggest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	suggest_row.add_child(suggest_label)
	use_button = RadioKit.small_button(host, "Use these", 26.0, 13)
	use_button.mouse_filter = Control.MOUSE_FILTER_PASS
	use_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	use_button.pressed.connect(use_suggested)
	suggest_row.add_child(use_button)
	prio.add_child(suggest_row)
	plan_label = _para("", 13, host.INK, 600)
	prio.add_child(plan_label)
	shift_label = _para("", 12, host.INK2)
	prio.add_child(shift_label)
	pins_row = host._hbox(8)
	pins_label = _para("", 12, host.INK2, 600)
	pins_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pins_row.add_child(pins_label)
	release_button = RadioKit.small_button(host, "Let the base decide", 26.0, 13)
	release_button.mouse_filter = Control.MOUSE_FILTER_PASS
	release_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	release_button.tooltip_text = "Hand the people you moved by hand back to the priorities: the base may move them again"
	release_button.pressed.connect(release_pins)
	pins_row.add_child(release_button)
	prio.add_child(pins_row)
	# Policies
	var pol := _section("policies", "Policies")
	dials = PolicyDials.new()
	pol.add_child(dials)
	dials.setup(host, sim_getter)
	# Facilities
	var fac := _section("facilities", "Facilities")
	_fac_box = host._vbox(3)
	fac.add_child(_fac_box)
	ok_toggle = RadioKit.small_button(host, "", 24.0, 12)
	ok_toggle.mouse_filter = Control.MOUSE_FILTER_PASS
	ok_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ok_toggle.pressed.connect(_toggle_ok)
	ok_toggle.visible = false
	fac.add_child(ok_toggle)
	_fac_ok_box = host._vbox(3)
	_fac_ok_box.visible = false
	fac.add_child(_fac_ok_box)
	# Trouble (the list is the problems view's; the page only mounts it)
	var trouble := _section("trouble", "Trouble")
	_trouble_box = host._vbox(4)
	trouble.add_child(_trouble_box)
	_trouble_empty = _para("No trouble now.", 13, host.INK3)
	_trouble_box.add_child(_trouble_empty)
	_mount_trouble()
	# (round 26: the demo has neither the four dials nor the trouble in the yard: their sections are not there at all)
	var sim0 = _sim()
	if sim0 != null and sim0.has_method("is_demo") and sim0.is_demo():
		sections.policies.visible = false
		sections.trouble.visible = false
	# the foot
	var foot: VBoxContainer = host._vbox(6)
	foot.add_child(_rule())
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 4)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jobs_button = RadioKit.small_button(host, "Jobs (advanced)", 28.0, 13)
	jobs_button.mouse_filter = Control.MOUSE_FILTER_PASS
	jobs_button.tooltip_text = "Jobs: one row for each person, their day job and night post, Fill empty seats and the station settings\nKey: J (Shift+J: the full page)"
	jobs_button.pressed.connect(_open_page.bind("jobs", ""))
	buttons.add_child(jobs_button)
	build_button = RadioKit.small_button(host, "Build", 28.0, 13)
	build_button.mouse_filter = Control.MOUSE_FILTER_PASS
	build_button.tooltip_text = "Build: order a building for the Builders to raise (priorities never order a building)\nKey: N (Shift+N: the full page)"
	build_button.pressed.connect(_open_page.bind("build", ""))
	buttons.add_child(build_button)
	foot.add_child(buttons)
	add_child(foot)


## A section: a rule, its title in small capitals and a box for its parts; `sections[id]` is the box.
func _section(id: String, title: String) -> VBoxContainer:
	var box: VBoxContainer = host._vbox(6)
	box.add_child(_rule())
	var t: Label = host._caps(title)
	box.add_child(t)
	add_child(box)
	titles[id] = t
	sections[id] = box
	return box


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = host.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _para(text: String, size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = host._label(text, Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _small(text: String, tip: String) -> Button:
	var b := RadioKit.small_button(host, text, 24.0, 12)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size.x = 44.0
	b.tooltip_text = tip
	return b


## The Trouble list of the problems view, when there is one: it is given the page contract's setup and kept.
func _mount_trouble() -> void:
	if trouble_list != null or not ResourceLoader.exists(PROBLEM_LIST_PATH):
		return
	var script = load(PROBLEM_LIST_PATH)
	if script == null or not script.can_instantiate():
		return
	var node = script.new()
	if not (node is Control):
		return
	_trouble_box.add_child(node)
	if node.has_method("setup"):
		node.setup(host, sim_getter, {"panel": options.get("panel")})
	if _compact and node.has_method("set_compact"):
		node.set_compact(true)
	trouble_list = node


# ---------------------------------------------------------------------- refreshing --

## Asks the sim again at once (the concerns are otherwise asked for every half second) and brings the page up to date.
func refresh_now() -> void:
	_concerns_at = -1000000
	refresh()


func refresh() -> void:
	if not _built:
		return
	_refresh_today()
	_refresh_priorities()
	if dials != null:
		dials.refresh()
	_refresh_facilities()
	_refresh_trouble()
	_refresh_focus()


# -------------------------------------------------------------------------- today --

## The concerns as the briefing ranks them now ([] without the module): up to MAX_CONCERNS, asked for at most twice a second.
func concerns() -> Array:
	var now := _now()
	if now - _concerns_at >= int(CONCERN_EVERY_S * 1000.0) or now < _concerns_at:
		_concerns_at = now
		_concerns = []
		var m = _mod("briefing")
		if m != null and m.has_method("concerns"):
			var raw = m.concerns()
			if raw is Array:
				for c in raw:
					if c is Dictionary and String(c.get("text", "")).strip_edges() != "":
						_concerns.append(c)
	return _concerns


func _refresh_today() -> void:
	var m = _mod("briefing")
	var all := concerns()
	var ranked: Array = []
	var fine: Array = []
	for c in all:
		if String(c.get("level", "info")) == "ok":
			fine.append(c)
		elif ranked.size() < MAX_CONCERNS:
			ranked.append(c)
	var sig := "%s|%s|%s" % [str(m != null), str(ranked), str(fine)]
	if sig != _today_sig:
		_today_sig = sig
		_rebuild_today(m != null, ranked, fine)
	_refresh_debrief()


func _rebuild_today(has_module: bool, ranked: Array, fine: Array) -> void:
	for c in _today_box.get_children():
		_today_box.remove_child(c)
		c.queue_free()
	today_rows.clear()
	if not has_module:
		_today_box.add_child(_para(NO_BRIEFING, 13, host.INK3))
		return
	for c in ranked:
		_today_box.add_child(_concern_row(c))
	if ranked.is_empty():
		_today_box.add_child(_para("Nothing needs you: the base is holding.", 13, host.INK2, 600))
	if not fine.is_empty():
		var words: Array = []
		for c in fine:
			words.append(String(c.text))
		_today_box.add_child(_para("Fine: %s" % "; ".join(words), 12, host.INK3))


## One concern: its icon, its words in the colour of its level, what is under them, and a button to where it is handled.
func _concern_row(c: Dictionary) -> Control:
	var level := String(c.get("level", "info"))
	var tone: Color = RadioKit.level_color(host, level)
	var id := String(c.get("id", ""))
	var row: HBoxContainer = host._hbox(7)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 1)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: TextureRect = host._icon(RadioKit.concern_icon(id, level), 16, tone)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pad.add_child(icon)
	row.add_child(pad)
	var col: VBoxContainer = host._vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text: Label = _para(String(c.get("text", "")), 13, tone, 600)
	col.add_child(text)
	var sub := String(c.get("sub", "")).strip_edges()
	if sub != "":
		col.add_child(_para(sub, 12, host.INK2))
	row.add_child(col)
	var page := String(c.get("page", ""))
	var entry := {"id": id, "row": row, "label": text, "button": null, "page": page, "focus": String(c.get("focus", ""))}
	if page != "" and PAGE_WORDS.has(page):
		var b := _small(String(PAGE_WORDS[page]), "Open the %s page: %s" % [String(PAGE_WORDS[page]), String(c.get("text", ""))])
		b.pressed.connect(go.bind(id))
		row.add_child(b)
		entry.button = b
	today_rows.append(entry)
	return row


## Opens the page that handles a concern (`host.open_radio(page, {"focus": focus})`). False when there is no such concern or it points nowhere.
func go(concern_id: String) -> bool:
	for e in today_rows:
		if String(e.id) == concern_id and String(e.page) != "":
			_open_page(String(e.page), String(e.focus))
			return true
	return false


func _open_page(page: String, focus: String) -> void:
	if host == null or not host.has_method("open_radio"):
		return
	if focus != "":
		host.open_radio(page, {"focus": focus})
	else:
		host.open_radio(page)


## The last evening's debrief: the latest "debrief" of the News, its head and its lines.
func _refresh_debrief() -> void:
	var radio = _mod("radio")
	var e := {}
	if radio != null and radio.get("news") is Array:
		for i in range((radio.news as Array).size() - 1, -1, -1):
			if String(radio.news[i].get("kind", "")) == "debrief":
				e = radio.news[i]
				break
	var items: Array = RadioKit.line_items(e) if not e.is_empty() else []
	var sig := "%s|%s|%s" % [str(e.get("id", 0)), String(e.get("text", "")), str(items)]
	if sig == _debrief_sig:
		return
	_debrief_sig = sig
	for c in _debrief_box.get_children():
		_debrief_box.remove_child(c)
		c.queue_free()
	debrief_labels.clear()
	if e.is_empty():
		return
	var head: Label = _para("%s (day %d)" % [String(e.get("text", "Evening")), int(e.get("day", 0))], 12, host.INK3, 600)
	_debrief_box.add_child(head)
	debrief_labels.append(head)
	for item in items:
		var level := String(item.level)
		var prefix := "Done: " if level == "ok" else ("Slipped: " if level == "warn" else "")
		var l: Label = _para("%s%s" % [prefix, String(item.text)], 12, RadioKit.level_color(host, level), 600)
		_debrief_box.add_child(l)
		debrief_labels.append(l)


# ------------------------------------------------------------------------- priorities --

func _on_chip(id: String) -> void:
	tap(id)


## A tap on a priority chip: the sim's `priorities.toggle` (the tap order is the rank; a fifth is refused in the sim's words, shown under the chips).
## {"ok", "why"}.
func tap(id: String) -> Dictionary:
	var r := PriorityKit.tap(_sim(), id)
	_note_answer("" if bool(r.get("ok", false)) else String(r.get("why", "")))
	_ui_sound(bool(r.get("ok", false)))
	refresh_now()
	return r


## Use these: the two ids the top concerns point at become the order. {"ok", "why"}.
func use_suggested() -> Dictionary:
	var r := PriorityKit.use_suggested(_sim())
	_note_answer("" if bool(r.get("ok", false)) else String(r.get("why", "")))
	_ui_sound(bool(r.get("ok", false)))
	refresh_now()
	return r


## Let the base decide: the people the player moved by hand may be moved by the plan again.
func release_pins() -> void:
	var m = _mod("priorities")
	if m != null and m.has_method("release_pins"):
		m.release_pins()
	_ui_sound(true)
	_plan_sig = ""
	refresh_now()


func _note_answer(text: String) -> void:
	_answer = {"text": text, "until": _now() + int(ANSWER_S * 1000.0)} if text != "" else {}
	answer_label.text = text
	answer_label.visible = text != ""


func _ui_sound(ok: bool) -> void:
	if host != null and host.has_method("ui_sound"):
		host.ui_sound("ui_confirm" if ok else "ui_error", 0.8)


func _refresh_priorities() -> void:
	var sim = _sim()
	PriorityKit.sync(host, chips, sim)
	if not _answer.is_empty() and _now() >= int(_answer.until):
		_answer = {}
		answer_label.visible = false
	var m = _mod("priorities")
	var order := PriorityKit.order_of(sim)
	var suggested := PriorityKit.suggested_of(sim)
	var plan := _plan_text(m, order)
	var shifts := _shift_text(m)
	var pins := _pins_text(m)
	var sig := "%s|%s|%s|%s|%s" % [str(order), str(suggested), plan, shifts, pins]
	if sig == _plan_sig:
		return
	_plan_sig = sig
	# nothing ranked: what the card would suggest, in one tap
	var usable := m != null
	suggest_row.visible = usable and order.is_empty() and not suggested.is_empty()
	if suggest_row.visible:
		suggest_label.text = "Suggested: %s" % PriorityKit.words_of(suggested)
		use_button.tooltip_text = "Set %s as your priorities: the first counts most" % PriorityKit.words_of(suggested)
	plan_label.text = plan
	plan_label.visible = plan != ""
	shift_label.text = shifts
	shift_label.visible = shifts != ""
	pins_label.text = pins
	pins_row.visible = pins != ""


## "What the base will do today: garden 2, bench 1, builders 1" (the sim's `seat_plan`); the words for nothing ranked.
func _plan_text(m, order: Array) -> String:
	if m == null:
		return "No priorities in this game."
	if order.is_empty():
		return "Nothing ranked: the jobs stay as they are."
	var plan = m.seat_plan() if m.has_method("seat_plan") else {}
	var parts: Array = []
	if plan is Dictionary:
		var ids: Array = (plan as Dictionary).keys()
		ids.sort_custom(func(a, b):
			var na := int(plan[a])
			var nb := int(plan[b])
			return na > nb if na != nb else String(a) < String(b))
		for id in ids:
			if int(plan[id]) > 0:
				parts.append("%s %d" % [_station_word(String(id)), int(plan[id])])
	if parts.is_empty():
		return "What the base will do today: nothing to move."
	return "What the base will do today: %s" % ", ".join(parts)


func _station_word(id: String) -> String:
	if STATION_WORDS.has(id):
		return String(STATION_WORDS[id])
	var jobs = _mod("jobs")
	var st: Dictionary = jobs.station(id) if jobs != null and jobs.has_method("station") else {}
	return String(st.get("name", id)).to_lower()


## What the priorities add to the wall line and to the bench's target, with the base numbers ("Wall line 70% + 15 = 85%").
func _shift_text(m) -> String:
	if m == null:
		return ""
	var jobs = _mod("jobs")
	var parts: Array = []
	var wall := float(m.wall_line_shift()) * 100.0 if m.has_method("wall_line_shift") else 0.0
	if absf(wall) >= 0.5 and jobs != null:
		var base := float(jobs.setting("builders", "repair_below"))
		var tactics = _mod("tactics")
		var total := float(tactics.repair_below()) * 100.0 if tactics != null and tactics.has_method("repair_below") else base + wall
		parts.append("Wall line %d%% %s %d = %d%%" % [int(roundf(base)), "+" if wall >= 0.0 else "-", int(roundf(absf(wall))), int(roundf(total))])
	var ammo := float(m.ammo_target_shift()) if m.has_method("ammo_target_shift") else 0.0
	if absf(ammo) >= 0.5 and jobs != null:
		var base2 := float(jobs.setting("bench", "ammo_target"))
		parts.append("Bench ammo target %d %s %d = %d" % [int(roundf(base2)), "+" if ammo >= 0.0 else "-", int(roundf(absf(ammo))), int(roundf(base2 + ammo))])
	return ". ".join(parts)


## "Pinned by you: Dez (Workbench)": who the base will not move back ("" when nobody is).
func _pins_text(m) -> String:
	if m == null or not m.has_method("pinned"):
		return ""
	var ids = m.pinned()
	if not (ids is Array) or (ids as Array).is_empty():
		return ""
	var s = _sim()
	var jobs = _mod("jobs")
	var who: Array = []
	for id in ids:
		for p in s.people:
			if String(p.id) == String(id) and not p.dead:
				var job: String = String(jobs.job_of(p)) if jobs != null else ""
				who.append("%s (%s)" % [String(p.first), _station_word(job).capitalize() if job != "" else "no job"])
	return "Pinned by you: %s" % ", ".join(who) if not who.is_empty() else ""


# ------------------------------------------------------------------------- policies --

## Sets a dial: the sim's own {"ok", "line", "why"} (the dial's answer line is under it).
func choose(dial: String, option: String) -> Dictionary:
	if dials == null:
		return {"ok": false, "line": "", "why": PolicyDials.OFF}
	return dials.choose(dial, option)


# ------------------------------------------------------------------------- facilities --

## The facilities as the briefing gives them ([] without the module).
func facilities() -> Array:
	var m = _mod("briefing")
	var out: Array = []
	if m != null and m.has_method("facilities"):
		var raw = m.facilities()
		if raw is Array:
			for f in raw:
				if f is Dictionary and String(f.get("id", "")) != "":
					out.append(f)
	return out


func _refresh_facilities() -> void:
	var list := facilities()
	var sig := "%s|%s" % [str(list), str(_show_ok)]
	if sig == _fac_sig:
		return
	_fac_sig = sig
	for box in [_fac_box, _fac_ok_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	facility_rows.clear()
	var working := 0
	for f in list:
		var ok := bool(f.get("ok", false))
		var entry := _facility_row(f)
		(_fac_ok_box if ok else _fac_box).add_child(entry.row)
		facility_rows[String(f.id)] = entry
		if ok:
			working += 1
	if list.is_empty():
		var none := _para("No stations to report on." if _mod("briefing") != null else NO_BRIEFING, 13, host.INK3)
		_fac_box.add_child(none)
	elif working == list.size():
		_fac_box.add_child(_para("Every station is working.", 13, host.INK2, 600))
	ok_toggle.visible = working > 0
	_fac_ok_box.visible = working > 0 and _show_ok
	ok_toggle.text = ("Hide the %d working" if _show_ok else "Show the %d working") % working
	ok_toggle.tooltip_text = "The stations that have what they need"


func _toggle_ok() -> void:
	_show_ok = not _show_ok
	_fac_sig = ""
	_refresh_facilities()


func _facility_row(f: Dictionary) -> Dictionary:
	var ok := bool(f.get("ok", false))
	var tone: Color = host.OK if ok else host.WARN
	var row: HBoxContainer = host._hbox(7)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(10, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.draw.connect(func(): dot.draw_circle(Vector2(5, 7), 4.0, tone))
	row.add_child(dot)
	var words := String(f.get("line", "")).strip_edges()
	if words == "":
		words = "%s: working" % String(f.get("name", f.id)) if ok else "%s: %s" % [String(f.get("name", f.id)), String(f.get("bottleneck", "waiting"))]
	var label: Label = _para(words, 13, host.INK2 if ok else host.INK, 600)
	row.add_child(label)
	var entry := {"row": row, "dot": dot, "label": label, "button": null, "ok": ok, "page": "", "focus": ""}
	var fix = f.get("fix", {})
	var page := String((fix as Dictionary).get("page", "")) if fix is Dictionary else ""
	if page != "" and PAGE_WORDS.has(page):
		var focus := String((fix as Dictionary).get("focus", ""))
		var b := _small(String(PAGE_WORDS[page]), "Open the %s page: %s" % [String(PAGE_WORDS[page]), words])
		b.pressed.connect(_open_page.bind(page, focus))
		row.add_child(b)
		entry.button = b
		entry.page = page
		entry.focus = focus
	return entry


## The lines of the not-working facilities, as printed (for the tests): by id.
func facility_lines() -> Dictionary:
	var out := {}
	for id in facility_rows:
		out[id] = String(facility_rows[id].label.text)
	return out


# --------------------------------------------------------------------------- trouble --

func _refresh_trouble() -> void:
	if trouble_list == null:
		_mount_trouble()
	if trouble_list != null and trouble_list.has_method("refresh"):
		trouble_list.refresh()
	# (the list says "No trouble now." itself; the page's own line is for a game that has no such view)
	_trouble_empty.visible = trouble_list == null


# ------------------------------------------------------------------------------ focus --

## Brings the eye to a part of the page: a priority id or "priorities" (the chips), a dial id or "policies" (the dials), a facility id, "problems" or
## "trouble" (the Trouble list), "today". The title of its section is lit for FOCUS_S seconds and the section is scrolled into view.
func focus_on(id: String) -> void:
	var section := ""
	if id == "" or id == "today":
		section = "today"
	elif PriorityKit.IDS.has(id) or id == "priorities":
		section = "priorities"
	elif PolicyDials.DIALS.has(id) or id == "policies" or id == "dials":
		section = "policies"
	elif facility_rows.has(id) or id == "facilities":
		section = "facilities"
	elif id == "problems" or id == "trouble":
		section = "trouble"
	elif trouble_list != null and trouble_list.get("rows") is Dictionary and (trouble_list.rows as Dictionary).has(id):
		section = "trouble"
		trouble_list.focus_on(id)
	if section == "":
		return
	_focus = {"id": id, "section": section}
	_focus_until = _now() + int(FOCUS_S * 1000.0)
	_refresh_focus()
	var scroller := _outer_scroll()
	if scroller != null:
		if section == "today":
			scroller.scroll_vertical = 0
		else:
			_scroll_to.call_deferred(sections[section])


func _refresh_focus() -> void:
	var lit := ""
	if not _focus.is_empty():
		if _now() < _focus_until:
			lit = String(_focus.section)
		else:
			_focus = {}
	for id in titles:
		var want: Color = host.ACCENT if String(id) == lit else host.INK3
		var label: Label = titles[id]
		if label.get_theme_color("font_color") != want:
			label.add_theme_color_override("font_color", want)


## The section that is lit now ("" for none), for the tests.
func lit_section() -> String:
	return String(_focus.get("section", "")) if not _focus.is_empty() and _now() < _focus_until else ""


func _outer_scroll() -> ScrollContainer:
	var n := get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func _scroll_to(node: Control) -> void:
	var sc := _outer_scroll()
	if sc != null and node != null and is_instance_valid(node) and node.is_inside_tree():
		sc.ensure_control_visible(node)


## The full page of the same name: the Duty roster, the advanced view of who works where.
func full_page() -> void:
	if host != null and host.has_method("open_jobs"):
		host.open_jobs()
