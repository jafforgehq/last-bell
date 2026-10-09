## The Jobs page of the radio panel (round 18, V2.2 JOBSUI): who works where by day and who holds which post at night, ASKED for
## over the radio. The modal Duty roster (jobs_screen.gd) stays as the full page (Shift+J, the "Full roster" button); this is the
## compact form that sits beside the yard, never pauses the game and takes no key.
##
## A row of two lines for each person at the base (the player first, "You: no seat, you are the player"; the dead at the foot, greyed
## with their word; the away greyed with theirs): line 1 the portrait (28 px), the first name, a word for the mood and what they are
## doing (cut short with an ellipsis, the whole in a tooltip); line 2 the buttons `Day: <station>` and `Night: <post>`. A button opens
## a list inline, under the row (never a popup): every station with its seats left and, for one that cannot be had, its reason in
## small amber text; or every post on the wall, grouped, with the holder named for a taken one. Choosing a line asks the radio
## (`radio.request_job` / `request_post`): the answer line, their words, stays under the row for six seconds, green when they are
## willing and plain when they are grudging; a soft refusal is amber with an Insist button (its cost in the tooltip) and a hard one
## has none. Every reason is the sim's (`radio.job_willingness`, `post_willingness`, `fill_willingness`): the page never writes one
## of its own. Under the rows the settings of the stations (a collapsed group of sliders, as the modal screen has them); at the foot
## Fill empty seats (the open seats go to people with no job, nobody is taken off one; each who could not has a line saying why)
## and Full roster (`host.open_jobs()`).
##
## Hovering a row or a line of a list marks the place in the world as the modal screen does (`host.set_jobs_hover`); while the page
## is shown every station is marked faintly, and when it is hidden or freed nothing is. Nothing here takes focus: the panel's
## controls are for the mouse, and WASD and E keep walking and using.
##
## The page is plain content: the radio panel keeps it in its own scroll and is as tall as the page asks (`get_combined_minimum_size`),
## so the foot comes after the last row (and the station settings, when they are open).
##
## The panel (radio_panel.gd) gives every page the same four functions: `setup(host, sim_getter, options)`, `refresh()` (every
## HUD update while it is open: cheap, a row is redrawn only when what it shows changed), `focus_on(id)` (a person: their row is
## lit and, with no job, the list of jobs opens for them; a station: a note says who holds it and how many seats are open) and
## `full_page()`. `wanted_height()` says how tall the page would like to be (for a panel that sizes itself to its content).
extends VBoxContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const MenuKit := preload("res://scripts/ui/menu_kit.gd")

## How long an answer stays under a row, the report of Fill empty seats stays at the foot and a focus stays lit (seconds).
const ANSWER_S := 6.0
const FILL_S := 10.0
const FOCUS_S := 4.0
const PORTRAIT_PX := 28
## The look of a row (an opaque slip a shade lighter than the panel, so that its words read over any world) and of a list under it.
const SLIP_BG := Color("#22362f")
const SLIP_HOVER := Color("#2c443b")
const SLIP_EDGE := Color(0.93, 0.96, 0.89, 0.16)
const LIST_BG := Color("#18241f")
## What the page says when the radio cannot be asked (a game with no radio of the round 18 kind).
const NO_RADIO := "No radio to ask: nobody can be given a job from here"

var host
var sim_getter: Callable
var options := {}
## person id -> {"person", "row" (the slip), "pic", "name", "mood", "doing", "job" (the day button), "post" (the night button), "line2",
## "you" (the player's line), "answer" (the label), "answer_row", "insist" (the button), "hover", "sig"}.
var rows := {}
## The list that is open (a panel inside `rows_box`), or null: its kind ("job" or "post"), the person it is for, its lines by id
## (a station's or a post's; "" is "No job") and the amber reason of each line that has one.
var list = null
var list_kind := ""
var list_for = null
var list_items := {}
var list_reasons := {}
## The amber line at the top of a list when the same soft reason holds for every line of it ("Ana: bleeding, can't take a job
## now": said once, not on each line), or null.
var list_shared = null
var rows_box: VBoxContainer
var stations_toggle: Button
var stations_box: VBoxContainer
## station id -> {setting -> HSlider}
var sliders := {}
var fill_button: Button
var full_button: Button
var fill_box: VBoxContainer
var focus_note: Label
var _built := false
var _foot: Control
## person id -> {"text", "color", "until" (ms), "kind", "id", "insist": whether the refusal can be pushed}.
var _answers := {}
var _fill_report := {}
var _fill_until := 0
var _focus := {}
var _focus_until := 0
## Milliseconds the page's clock has been moved on (tests: `skip_ahead`).
var _skipped := 0
var _marks := {}
var _marks_on := false
var _list_sig := ""
var _foot_sig := ""
var _order_sig := ""
var _value_labels := {}
var _sliders_built := false


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
	add_theme_constant_override("separation", 6)
	_build()
	refresh()


# ------------------------------------------------------------------ build --

func _build() -> void:
	focus_note = host._label("", Fonts.sans(600), 13, host.ACCENT)
	focus_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	focus_note.custom_minimum_size.x = 60
	focus_note.visible = false
	add_child(focus_note)

	# the rows and what is under them are the page itself: the radio panel scrolls its page (and sizes itself to what the page
	# asks for, `get_combined_minimum_size`), so a scroll of this page's own would be a second one
	rows_box = host._vbox(4)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(rows_box)

	# the stations' settings: a group that is collapsed until it is asked for
	stations_toggle = _button("Station settings", 28.0)
	stations_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stations_toggle.tooltip_text = "Station settings: the bench's ammo target and scrap reserve, the wall crew's threshold"
	stations_toggle.pressed.connect(_toggle_stations)
	add_child(stations_toggle)
	stations_box = host._vbox(8)
	stations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stations_box.visible = false
	add_child(stations_box)

	var foot: VBoxContainer = host._vbox(5)
	fill_box = host._vbox(2)
	fill_box.visible = false
	foot.add_child(fill_box)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 4)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_button = _button("Fill empty seats", 28.0)
	fill_button.pressed.connect(fill)
	buttons.add_child(fill_button)
	full_button = _button("Full roster", 28.0)
	full_button.tooltip_text = "Full roster: the whole Duty roster, with skills, the stations' seats and Auto-assign\nKey: Shift+J"
	full_button.pressed.connect(full_page)
	buttons.add_child(full_button)
	foot.add_child(buttons)
	_foot = foot
	add_child(foot)
	_build_sliders()


## A small button of the radio's kind that the wheel can pass through (the page scrolls under the mouse).
func _button(text: String, height: float = 26.0) -> Button:
	var b: Button = RadioKit.small_button(host, text, height, 13)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _slip_style(lit: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SLIP_HOVER if lit else SLIP_BG
	s.border_color = host.ACCENT if lit else SLIP_EDGE
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.anti_aliasing = true
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


func _make_row(p) -> Dictionary:
	var id := String(p.id)
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", _slip_style(false))
	var col: VBoxContainer = host._vbox(4)
	row.add_child(col)
	var r := {"person": p, "row": row, "hover": false, "sig": ""}

	# line 1: who they are and what they are doing
	var line1: HBoxContainer = host._hbox(6)
	var pic := TextureRect.new()
	pic.texture = host.portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_PASS
	pic.tooltip_text = "%s, %s" % [p.name, String(p.def.get("role", "")).to_lower()]
	line1.add_child(pic)
	var name_label: Label = host._label(String(p.first), Fonts.cond(700), 15, host.INK)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line1.add_child(name_label)
	var mood: Label = host._label("", Fonts.sans(600), 12, host.INK2)
	mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line1.add_child(mood)
	var doing: Label = host._label("", Fonts.sans(400), 13, host.INK2)
	doing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	doing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	doing.clip_text = true
	doing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	doing.custom_minimum_size.x = 30
	doing.mouse_filter = Control.MOUSE_FILTER_PASS
	line1.add_child(doing)
	col.add_child(line1)

	# line 2: the day job and the night post, as buttons that open a list (the player's line says there is no seat)
	var line2: HBoxContainer = host._hbox(6)
	var job := _row_button()
	job.pressed.connect(_on_job_button.bind(p))
	line2.add_child(job)
	var post := _row_button()
	post.pressed.connect(_on_post_button.bind(p))
	line2.add_child(post)
	col.add_child(line2)
	var you: Label = host._label("You: no seat, you are the player", Fonts.sans(600), 13, host.INK2)
	you.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	you.custom_minimum_size.x = 60
	you.visible = false
	col.add_child(you)
	# (One House, CREW: a Scavenger's third line: what they have found today)
	var loot: Label = host._label("", Fonts.sans(600), 12, host.INK2)
	loot.visible = false
	loot.clip_text = true
	loot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	loot.custom_minimum_size.x = 30
	loot.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(loot)

	# under them: what they said to the last request, and Insist after a refusal that can be pushed
	var answer_row: HBoxContainer = host._hbox(6)
	answer_row.visible = false
	var answer: Label = host._label("", Fonts.sans(600), 13, host.INK)
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	answer.custom_minimum_size.x = 60
	answer.mouse_filter = Control.MOUSE_FILTER_PASS
	answer_row.add_child(answer)
	var insist_button := _button("Insist", 26.0)
	insist_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	insist_button.visible = false
	insist_button.pressed.connect(insist.bind(p))
	answer_row.add_child(insist_button)
	col.add_child(answer_row)

	r["pic"] = pic
	r["name"] = name_label
	r["mood"] = mood
	r["doing"] = doing
	r["line2"] = line2
	r["job"] = job
	r["post"] = post
	r["you"] = you
	r["loot"] = loot
	r["answer"] = answer
	r["answer_row"] = answer_row
	r["insist"] = insist_button
	row.mouse_entered.connect(_on_row_hover.bind(p, true))
	row.mouse_exited.connect(_on_row_exit.bind(p))
	for c in [job, post]:
		c.mouse_entered.connect(_on_row_hover.bind(p, true))
		c.mouse_exited.connect(_on_row_exit.bind(p))
	rows[id] = r
	return r


## One of the two buttons of a row: its words cut short with an ellipsis when the row is narrow (the tooltip has them whole).
func _row_button() -> Button:
	var b := _button("", 26.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.x = 40
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


# ------------------------------------------------------------------ the game --

func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _radio():
	var s = _sim()
	return s.get("radio") if s != null else null


## Whether the radio can be asked for work at all (a radio of round 18: a stand-in or an older one cannot).
func _can_ask(radio) -> bool:
	return radio != null and radio.has_method("job_willingness") and radio.has_method("request_job")


func _person(id: String):
	var s = _sim()
	if s == null:
		return null
	for p in s.people:
		if String(p.id) == id:
			return p
	return null


func _is_you(p) -> bool:
	var s = _sim()
	return bool(p.player) or (s != null and String(s.player_id) != "" and String(p.id) == String(s.player_id))


func _gone(p) -> bool:
	return p.dead or p.turned


func _now() -> int:
	return Time.get_ticks_msec() + _skipped


## Moves the page's clock on (for a test: the answers, the fill report and the focus have their seconds).
func skip_ahead(seconds: float) -> void:
	_skipped += int(seconds * 1000.0)


func _job_w(p, station_id: String) -> Dictionary:
	var radio = _radio()
	if not _can_ask(radio):
		return {"ok": false, "hard": true, "why": NO_RADIO, "line": "", "tone": "refused"}
	return radio.job_willingness(p, station_id)


func _post_w(p, post_id: String) -> Dictionary:
	var radio = _radio()
	if radio == null or not radio.has_method("post_willingness"):
		return {"ok": false, "hard": true, "why": NO_RADIO, "line": "", "tone": "refused"}
	return radio.post_willingness(p, post_id)


## Whether the buttons of a row are off for this person, and why: only a refusal that nobody can argue with (down, away, gone, the
## player...) turns them off; a soft one is asked for and answered in words.
func _block(p) -> Dictionary:
	var w := _job_w(p, "")
	if not bool(w.get("ok", true)) and bool(w.get("hard", false)):
		var why := String(w.get("why", ""))
		return {"off": true, "why": why if why != "" else "%s cannot be given a job now" % String(p.first)}
	return {"off": false, "why": String(w.get("why", ""))}


## Every station the game has, the built ones first (in the data's order) and then the ones whose building is not up yet.
func _all_stations() -> Array:
	var s = _sim()
	if s == null:
		return []
	var jobs = s.jobs
	var out: Array = []
	var seen := {}
	for st in jobs.stations():
		out.append(st)
		seen[String(st.id)] = true
	var every = jobs.get("_stations")
	if every is Array:
		for st in every:
			var id := String(st.id)
			if not seen.has(id):
				var now: Dictionary = jobs.station(id)
				out.append(now if not now.is_empty() else st)
	return out


func _station_name(id: String) -> String:
	var s = _sim()
	var st: Dictionary = s.jobs.station(id) if s != null else {}
	return String(st.get("name", id))


# --------------------------------------------------------------------- refresh --

## Brings the page in line with the game: the rows (each only when what it shows has changed), the open list, the foot.
func refresh() -> void:
	if host == null or not _built:
		return
	_sync_marks()
	var s = _sim()
	if s == null:
		return
	_expire()
	_build_sliders()
	_sync_rows(s)
	for p in s.people:
		var r: Dictionary = rows[String(p.id)]
		var sig := _row_sig(s, p, r)
		if sig != String(r.sig):
			r["sig"] = sig
			_refresh_row(s, p, r)
	_refresh_list()
	_refresh_foot(s)
	_refresh_sliders(s)
	_refresh_focus_note(s)


## Everything of a row is redrawn at once (after the person was asked something).
func _refresh_now() -> void:
	for id in rows:
		rows[id]["sig"] = ""
	_foot_sig = ""
	refresh()


func _expire() -> void:
	var now := _now()
	for id in _answers.keys():
		if int(_answers[id].until) <= now:
			_answers.erase(id)
			if rows.has(id):
				rows[id]["sig"] = ""
	if not _fill_report.is_empty() and _fill_until <= now:
		_fill_report = {}
		_foot_sig = ""
	if not _focus.is_empty() and _focus_until <= now:
		_focus = {}
		for id in rows:
			rows[id]["sig"] = ""
		_marks_for_focus(false)


## Makes a row for each person that has none, drops the rows of people who are no longer there, and puts the rows in order: the
## player, then the crew in its own order, then the ones who are gone.
func _sync_rows(s) -> void:
	var have := {}
	for p in s.people:
		have[String(p.id)] = true
		if not rows.has(String(p.id)):
			var r := _make_row(p)
			rows_box.add_child(r.row)
			_order_sig = ""
	for id in rows.keys():
		if not have.has(id):
			if list != null and list_for != null and String(list_for.id) == id:
				close_list(false)
			rows_box.remove_child(rows[id].row)
			rows[id].row.queue_free()
			rows.erase(id)
			_answers.erase(id)
			_order_sig = ""
	var ordered: Array = []
	var rank := 0
	for p in s.people:
		ordered.append([0 if _is_you(p) else (2 if _gone(p) else 1), rank, String(p.id)])
		rank += 1
	ordered.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var sig := ""
	for e in ordered:
		sig += String(e[2]) + ","
	if sig == _order_sig:
		return
	_order_sig = sig
	var at := 0
	for e in ordered:
		var node: Control = rows[String(e[2])].row
		rows_box.move_child(node, at)
		at += 1
		if list != null and list_for != null and String(list_for.id) == String(e[2]):
			rows_box.move_child(list, at)
			at += 1


func _row_sig(s, p, r: Dictionary) -> String:
	var block := _block(p)
	var answer: Dictionary = _answers.get(String(p.id), {})
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [p.dead, p.turned, p.away != null, p.downed, _is_you(p), s.jobs.job_of(p), s.jobs.post_of(p).get("id", ""),
		host._doing_person(p), _mood_of(s, p)[0], block.off, block.why, String(answer.get("text", "")), bool(answer.get("insist", false)), _lit(p, r), _loot_of(s, p)]


## One House, CREW: what a Scavenger has found today ("Found today: 4 food, 2 scrap"); "" for everybody else.
func _loot_of(s, p) -> String:
	var cs = s.get("crew_search")
	if cs == null or String(s.jobs.job_of(p)) != "scavenger":
		return ""
	return String(cs.today_text(p))


## [the word for how they are, its colour]: what has become of them, else their mood.
func _mood_of(s, p) -> Array:
	var word := String(host._card_word(p))
	if word != "":
		return [word, host.DANGER_TEXT if word == "Turned" else (host.INFO if word == "Away" else host.INK3)]
	var m = s.get("morale")
	if m == null or m.get("enabled") == false:
		return ["", host.INK2]
	if m.has_method("breakdown") and bool(m.breakdown(p)):
		return ["Breakdown", host.DANGER_TEXT]
	var mood := String(m.mood(p))
	return [mood, host.MOOD_TEXT.get(mood, host.INK2)]


func _lit(p, r: Dictionary) -> bool:
	if bool(r.get("hover", false)):
		return true
	if _focus.is_empty():
		return false
	if String(_focus.kind) == "person":
		return String(_focus.id) == String(p.id)
	var s = _sim()
	return s != null and String(s.jobs.job_of(p)) == String(_focus.id)


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _refresh_row(s, p, r: Dictionary) -> void:
	var gone := _gone(p)
	var you := _is_you(p) and not gone
	var jobs = s.jobs
	r.row.add_theme_stylebox_override("panel", _slip_style(_lit(p, r)))
	var mood := _mood_of(s, p)
	_set_text(r.mood, String(mood[0]), mood[1])
	_set_text(r.name, String(p.first), host.INK3 if gone else host.INK)
	var doing := String(host._doing_person(p))
	_set_text(r.doing, doing, host.INK3 if gone else host.INK2)
	r.doing.tooltip_text = doing
	# the buttons: what they are, and whether they can be pressed
	var job_id := String(jobs.job_of(p))
	var st: Dictionary = jobs.station(job_id)
	var post: Dictionary = jobs.post_of(p)
	r.job.text = "Day: %s" % (String(st.name) if not st.is_empty() else "no job")
	r.post.text = "Night: %s" % String(post.get("name", "no post"))
	var block := _block(p)
	r.line2.visible = not gone and not you
	r.you.visible = you
	var loot_text := _loot_of(s, p)
	r.loot.visible = loot_text != "" and not gone and not you
	_set_text(r.loot, loot_text, host.INK2)
	r.loot.tooltip_text = loot_text
	if you:
		# (the sim's own words for it: "You: no seat, you are the player")
		var said := String(_job_w(p, "").get("why", ""))
		_set_text(r.you, said if said != "" and said != NO_RADIO else "You: no seat, you are the player", host.INK2)
	r.job.disabled = bool(block.off)
	r.post.disabled = bool(block.off)
	r.job.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if block.off else Control.CURSOR_POINTING_HAND
	r.post.mouse_default_cursor_shape = r.job.mouse_default_cursor_shape
	if bool(block.off):
		r.job.tooltip_text = String(block.why)
		r.post.tooltip_text = String(block.why)
	else:
		var soft := ("\n" + String(block.why)) if String(block.why) != "" else ""
		var no_job := String(jobs.no_job_text())
		r.job.tooltip_text = ("Day job for %s: %s (%s)\nClick to ask for another." % [p.first, String(st.name), String(st.get("where", ""))] if not st.is_empty() else "Day job for %s: none. They %s by day.\nClick to ask for one." % [p.first, no_job]) + soft
		r.post.tooltip_text = "Night post for %s: %s\nWhere they hold the wall from the bell until dawn. Click to ask for another." % [p.first, String(post.get("name", "none"))] + soft
		if jobs.on_patrol(p):
			r.post.tooltip_text = "%s is on patrol: from the bell (or the call to arms) until dawn they walk the fence line by themselves and go where the dead press.\nClick to ask for a post instead (a tower, a stretch of fence)." % p.first + soft
	# the last answer
	var answer: Dictionary = _answers.get(String(p.id), {})
	r.answer_row.visible = not answer.is_empty()
	r.answer.visible = not answer.is_empty()
	if not answer.is_empty():
		_set_text(r.answer, String(answer.text), answer.color)
		r.answer.tooltip_text = String(answer.text)
	r.insist.visible = bool(answer.get("insist", false))
	if r.insist.visible:
		r.insist.tooltip_text = _insist_tip()


func _insist_tip() -> String:
	var radio = _radio()
	var trust := 6
	var morale := 4
	if radio != null:
		trust = int(radio.get("INSIST_COST") if radio.get("INSIST_COST") != null else 6)
		morale = int(absf(float(radio.get("INSIST_MORALE") if radio.get("INSIST_MORALE") != null else -4.0)))
	return "Insist: ask again and push them to do it anyway.\nIt costs trust -%d and mood -%d, and they will do it grudgingly." % [trust, morale]


# ----------------------------------------------------------------- the marks --

## The place of a station, a night post and/or a person is marked in the world (the overlay draws it): "" for nothing of the kind.
## With no arguments only the stations are marked, faintly, as long as the page is shown.
func show_marks(station: String = "", post: String = "", person: String = "") -> void:
	if host == null or not _marks_on:
		return
	var m := {"station": station, "post": post, "person": person}
	if m == _marks:
		return
	_marks = m
	if host.has_method("set_jobs_hover"):
		host.set_jobs_hover(m)


## The marks follow whether the page is shown: faint stations while it is, nothing when it is hidden or gone.
func _sync_marks() -> void:
	if host == null or not is_instance_valid(host):
		return
	var on := is_visible_in_tree()
	if on == _marks_on:
		# (the modal roster, closed again, takes its marks away with it: the faint stations of this page come back)
		if on and host.get("jobs_hover") is Dictionary and host.jobs_hover.is_empty() and host.has_method("set_jobs_hover"):
			host.set_jobs_hover(_marks if not _marks.is_empty() else {"station": "", "post": "", "person": ""})
		return
	_marks_on = on
	_marks = {}
	if on:
		show_marks()
	elif host.has_method("set_jobs_hover"):
		host.set_jobs_hover({})


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _built:
		_sync_marks()
	elif what == NOTIFICATION_EXIT_TREE and _built:
		_marks_on = false
		_marks = {}
		if host != null and is_instance_valid(host) and host.has_method("set_jobs_hover"):
			host.set_jobs_hover({})


func _on_row_hover(p, on: bool) -> void:
	var id := String(p.id)
	if not rows.has(id):
		return
	var r: Dictionary = rows[id]
	r["hover"] = on
	r["sig"] = ""
	r.row.add_theme_stylebox_override("panel", _slip_style(_lit(p, r)))
	var s = _sim()
	if on and s != null:
		show_marks(String(s.jobs.job_of(p)), String(s.jobs.post_of(p).get("id", "")), id)
	elif _marks.get("person", "") == id and list == null:
		show_marks()


## The mouse left the row (or went on to a button in it: a child that takes the mouse makes the row's own exit fire).
func _on_row_exit(p) -> void:
	var id := String(p.id)
	if not rows.has(id):
		return
	var row: Control = rows[id].row
	if row.is_inside_tree() and row.get_global_rect().has_point(row.get_global_mouse_position()):
		return
	_on_row_hover(p, false)


func _marks_for_focus(on: bool) -> void:
	if on and not _focus.is_empty() and String(_focus.kind) == "station":
		show_marks(String(_focus.id))
	elif _marks.get("station", "") != "" and _marks.get("person", "") == "" and _marks.get("post", "") == "":
		show_marks()


# ----------------------------------------------------------------- the lists --

func _on_job_button(p) -> void:
	if list != null and list_kind == "job" and list_for == p:
		close_list()
	else:
		open_job_list(p)


func _on_post_button(p) -> void:
	if list != null and list_kind == "post" and list_for == p:
		close_list()
	else:
		open_post_list(p)


## The day job list for `p`, inline under their row: every station with the seats it has left, and for one that cannot be had
## its reason (the radio's words); then "No job".
func open_job_list(p) -> void:
	if p == null or not rows.has(String(p.id)):
		return
	_open_list("job", p, _job_entries(p))


## The night post list for `p`: the posts on the wall by part, a taken one with its holder named.
func open_post_list(p) -> void:
	if p == null or not rows.has(String(p.id)):
		return
	_open_list("post", p, _post_entries(p))


## The lines of the day job list: {"id", "text", "note", "why", "off", "current", "tip"}. Pure: what the game says now.
func _job_entries(p) -> Array:
	var s = _sim()
	var jobs = s.jobs
	var have := String(jobs.job_of(p))
	var out: Array = []
	for st in _all_stations():
		var id := String(st.id)
		var current := id == have
		var unbuilt := bool(st.get("locked", false))
		var left: int = jobs.seats_left(id)
		var w := _job_w(p, id)
		var ok := bool(w.get("ok", false))
		var hard := bool(w.get("hard", true))
		var why := "" if current or ok else String(w.get("why", ""))
		var note := "current" if current else ("" if unbuilt else ("%d left" % left if left > 0 else "full"))
		var tip := "%s (%s)\n%s" % [String(st.name), String(st.get("where", "")), host._wrap(String(st.get("blurb", "")))]
		if current:
			tip = "%s has this job already" % p.first
		elif not ok and hard:
			tip = why if why != "" else "%s cannot take this job now" % p.first
		elif not ok:
			tip = "%s\nAsk anyway: they will say so, and Insist overrides it at a cost of trust" % why
		out.append({"id": id, "text": String(st.name), "note": note, "why": why, "off": current or (not ok and hard), "current": current, "tip": tip})
	var w := _job_w(p, "")
	var ok := bool(w.get("ok", false))
	var hard := bool(w.get("hard", true))
	var why := "" if ok else String(w.get("why", ""))
	out.append({"id": "", "text": "No job", "note": "current" if have == "" else "", "why": why, "off": have == "" or (not ok and hard), "current": have == "",
		"tip": "%s has no job already" % p.first if have == "" else (why if (not ok and hard) else "No day job: they %s by day" % String(jobs.no_job_text()))})
	return out


func _post_entries(p) -> Array:
	var s = _sim()
	var have := String(s.jobs.post_of(p).get("id", ""))
	var out: Array = []
	var group := ""
	if s.jobs.patrol_on():
		# (One House, PATROL: no post to keep: they walk the fence line and go where the dead press; the posts below are the ones the player gives)
		var patrolling: bool = have == s.jobs.PATROL
		var pw := _post_w(p, s.jobs.PATROL)
		var pok := bool(pw.get("ok", false))
		var phard := bool(pw.get("hard", true))
		var pwhy := "" if patrolling or pok else String(pw.get("why", ""))
		out.append({"header": "On the fence line"})
		out.append({"id": s.jobs.PATROL, "text": "Patrol", "note": "current" if patrolling else "automatic", "why": pwhy, "off": patrolling or (not pok and phard), "current": patrolling,
			"tip": "%s already walks the fence" % p.first if patrolling else "Patrol: walks the fence line by themselves and goes where the dead press, from the bell (or the call to arms) until dawn. No post to keep."})
	for po in s.jobs.posts():
		var id := String(po.id)
		var g := _post_group(s, po)
		if g != group:
			group = g
			out.append({"header": g})
		var current := id == have
		var w := _post_w(p, id)
		var ok := bool(w.get("ok", false))
		var hard := bool(w.get("hard", true))
		var why := "" if current or ok else String(w.get("why", ""))
		var tip := String(po.name)
		if current:
			tip = "%s holds this post already" % p.first
		elif not ok and hard:
			tip = why if why != "" else "%s cannot take this post now" % p.first
		elif not ok:
			tip = "%s\nAsk anyway: they will say so, and Insist overrides it at a cost of trust" % why
		out.append({"id": id, "text": String(po.name), "note": "current" if current else "", "why": why, "off": current or (not ok and hard), "current": current, "tip": tip})
	return out


## Which part of the wall a post is on, for the headings. The posts of the lots that are claimed (round 9: "post_<mouth id>") are
## grouped under the name of their lot, whatever side of the compound they look at.
func _post_group(s, po: Dictionary) -> String:
	var id := String(po.id)
	if id.begins_with("tower"):
		return "Towers"
	if id.begins_with("post_") and s.get("lots") != null:
		var m: Dictionary = s.lots.mouth(id.trim_prefix("post_"))
		var lot: Dictionary = s.lots.lot(String(m.get("lot", "")))
		if not lot.is_empty():
			return String(lot.name)
	match String(po.get("face", "N")):
		"W":
			return "West wall"
		"E":
			return "East wall"
	return "North wall"


func _list_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = LIST_BG
	s.border_color = Color(host.INK, 0.28)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.anti_aliasing = true
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 5
	s.content_margin_bottom = 6
	return s


func _open_list(kind: String, p, entries: Array) -> void:
	close_list(false)
	list_kind = kind
	list_for = p
	_build_list(entries)
	_list_sig = str(entries)
	var row: Control = rows[String(p.id)].row
	rows_box.move_child(list, row.get_index() + 1)
	show_marks()
	_scroll_to.call_deferred(list)


func _build_list(entries: Array) -> void:
	var p = list_for
	var pop := PanelContainer.new()
	pop.mouse_filter = Control.MOUSE_FILTER_PASS
	pop.add_theme_stylebox_override("panel", _list_style())
	var col: VBoxContainer = host._vbox(2)
	pop.add_child(col)
	var head: HBoxContainer = host._hbox(6)
	var title: Label = host._caps(("Day job for %s" if list_kind == "job" else "Night post for %s") % p.first, host.INK2)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(host._spacer())
	var close_button := _button("Close", 24.0)
	close_button.tooltip_text = "Close the list"
	close_button.pressed.connect(close_list)
	head.add_child(close_button)
	col.add_child(head)
	list_items = {}
	list_reasons = {}
	list_shared = null
	var shared := _shared_reason(entries)
	if shared != "":
		list_shared = host._label(shared, Fonts.sans(600), 12, host.WARN)
		list_shared.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list_shared.custom_minimum_size.x = 60
		list_shared.tooltip_text = "%s\nAsk anyway: they will say so, and Insist overrides it at a cost of trust" % shared
		list_shared.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(list_shared)
	for e in entries:
		if e.has("header"):
			var h: Label = host._caps(String(e.header), host.INK3)
			h.set_meta("header", true)
			var hp := MarginContainer.new()
			hp.add_theme_constant_override("margin_top", 4)
			hp.add_theme_constant_override("margin_left", 4)
			hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hp.add_child(h)
			col.add_child(hp)
			continue
		var slot: VBoxContainer = host._vbox(0)
		var b := _list_item(e)
		slot.add_child(b)
		var why := String(e.why)
		if why != "" and why == shared and not bool(e.off):
			why = ""    # (said once, at the top)
		if why != "":
			var wrap := MarginContainer.new()
			wrap.add_theme_constant_override("margin_left", 8)
			wrap.add_theme_constant_override("margin_right", 4)
			wrap.add_theme_constant_override("margin_bottom", 3)
			wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var reason: Label = host._label(why, Fonts.sans(600), 12, host.WARN)
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason.custom_minimum_size.x = 60
			wrap.add_child(reason)
			slot.add_child(wrap)
			list_reasons[String(e.id)] = reason
		col.add_child(slot)
		list_items[String(e.id)] = b
	list = pop
	rows_box.add_child(pop)


## The soft reason that holds for several lines of a list at once (a person who is bleeding cannot take any job), or "".
func _shared_reason(entries: Array) -> String:
	var found := ""
	var n := 0
	for e in entries:
		if e.has("header") or bool(e.off) or String(e.why) == "":
			continue
		if found != "" and String(e.why) != found:
			return ""
		found = String(e.why)
		n += 1
	return found if n >= 2 else ""


## One line of a list: the name, and at the right what is to be said about it (seats left, "current"). Off for a refusal nobody can
## argue with and for what the person has already; a soft refusal can be pressed.
func _list_item(e: Dictionary) -> Button:
	var off := bool(e.off)
	var current := bool(e.current)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if off else Control.CURSOR_POINTING_HAND
	b.disabled = off
	b.custom_minimum_size = Vector2(0, 28)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, _item_style(state, current))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.tooltip_text = String(e.tip)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	var inner: HBoxContainer = host._hbox(8)
	var ink: Color = host.INK3 if off and not current else host.INK
	var text: Label = host._label(String(e.text), Fonts.sans(600), 14, ink)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.custom_minimum_size.x = 30
	inner.add_child(text)
	var note := String(e.note)
	if note != "":
		var n: Label = host._label(note, Fonts.cond(700), 13, host.ACCENT if current else (host.INK3 if off else host.INK2))
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(n)
	pad.add_child(inner)
	b.add_child(pad)
	var id := String(e.id)
	b.set_meta("id", id)
	b.pressed.connect(_on_pick.bind(id))
	b.mouse_entered.connect(_mark_item.bind(id))
	return b


func _item_style(state: String, current: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(host.ACCENT, 0.16) if current else Color(0, 0, 0, 0)
	s.set_corner_radius_all(4)
	if state == "hover":
		s.bg_color = SLIP_HOVER
	elif state == "pressed":
		s.bg_color = SLIP_HOVER.lightened(0.06)
	if current:
		s.border_color = Color(host.ACCENT, 0.5)
		s.set_border_width_all(1)
	return s


## A line of the list is under the mouse: its place is marked in the world.
func _mark_item(id: String) -> void:
	var who := String(list_for.id) if list_for != null else ""
	if list_kind == "post":
		show_marks("", id, who)
	elif id != "":
		show_marks(id, "", who)
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


## Puts the list away.
func close_list(do_marks: bool = true) -> void:
	if list == null:
		return
	_drop_list_node()
	list_items = {}
	list_reasons = {}
	list_shared = null
	list_kind = ""
	list_for = null
	_list_sig = ""
	if do_marks:
		show_marks()


## An open list follows the game: it is made again only when one of its lines would say something different.
func _refresh_list() -> void:
	if list == null or list_for == null:
		return
	var entries: Array = _job_entries(list_for) if list_kind == "job" else _post_entries(list_for)
	var sig := str(entries)
	if sig == _list_sig:
		return
	var p = list_for
	_drop_list_node()
	_build_list(entries)
	_list_sig = sig
	rows_box.move_child(list, rows[String(p.id)].row.get_index() + 1)


func _drop_list_node() -> void:
	if list == null:
		return
	if list.get_parent() != null:
		list.get_parent().remove_child(list)
	list.queue_free()
	list = null


## The scroll the panel keeps this page in (null when the page stands on its own, as in a test).
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


# ---------------------------------------------------------------- choosing --

## Asks for `p` to be given the day job `id` ("" takes them off it). Returns the radio's answer ({"ok", "line", "why", "hard", ...}); the
## page shows it under the row. With `insist` a refusal that is not a hard one is overridden, at a cost of trust.
func choose_job(p, id: String, insist_on: bool = false) -> Dictionary:
	var radio = _radio()
	if p == null or not _can_ask(radio):
		return _no_radio()
	var ans: Dictionary = radio.request_job(p, id, {"insist": true} if insist_on else {}).duplicate()
	_noted(p, "job", id, ans)
	return ans


## The same for a night post.
func choose_post(p, id: String, insist_on: bool = false) -> Dictionary:
	var radio = _radio()
	if p == null or radio == null or not radio.has_method("request_post"):
		return _no_radio()
	var ans: Dictionary = radio.request_post(p, id, {"insist": true} if insist_on else {}).duplicate()
	_noted(p, "post", id, ans)
	return ans


func _no_radio() -> Dictionary:
	return {"ok": false, "line": "", "why": NO_RADIO, "hard": true, "tone": "refused", "insisted": false}


## Pushes: asks again for what was refused softly under `p`'s row.
func insist(p) -> Dictionary:
	var last: Dictionary = _answers.get(String(p.id), {})
	if last.is_empty() or not bool(last.get("insist", false)):
		return {}
	if String(last.kind) == "job":
		return choose_job(p, String(last.id), true)
	return choose_post(p, String(last.id), true)


## What the radio said is kept under the row for ANSWER_S seconds, in the colour of the answer.
func _noted(p, kind: String, id: String, ans: Dictionary) -> void:
	var ok := bool(ans.get("ok", false))
	var text := ""
	var color: Color = host.INK
	if ok:
		text = "%s: %s" % [p.first, String(ans.get("line", ""))]
		color = host.OK if String(ans.get("tone", "")) == "willing" else host.INK
	else:
		text = String(ans.get("why", ""))
		if text == "":
			text = "%s cannot do that now" % p.first
		color = host.WARN
	_answers[String(p.id)] = {"text": text, "color": color, "until": _now() + int(ANSWER_S * 1000.0), "kind": kind, "id": id, "insist": not ok and not bool(ans.get("hard", true))}
	_sound("ui_click" if ok else "ui_error")
	_refresh_now()


func _sound(sound_name: String) -> void:
	if host != null and host.has_method("ui_sound"):
		host.ui_sound(sound_name)


## The words of the sim for why `p` cannot have this station or post ("" when they can): what the lists and the answers show.
func reason_for(p, id: String) -> String:
	var s = _sim()
	if s == null or p == null:
		return ""
	var w: Dictionary = _job_w(p, id) if not s.jobs.station(id).is_empty() or id == "" else _post_w(p, id)
	return "" if bool(w.get("ok", false)) else String(w.get("why", ""))


# -------------------------------------------------------------------- the foot --

## Fill empty seats: the open seats go to the people with no job (the radio asks `jobs.fill_empty`: nobody is taken off a job).
## Returns the radio's answer; the lines for each who could not, and why, stay at the foot.
func fill() -> Dictionary:
	var radio = _radio()
	if radio == null or not radio.has_method("request_fill"):
		return {"ok": false, "assigned": [], "stuck": [], "line": NO_RADIO}
	var r: Dictionary = radio.request_fill().duplicate(true)
	_fill_report = r
	_fill_until = _now() + int(FILL_S * 1000.0)
	_sound("ui_confirm" if bool(r.get("ok", false)) else "ui_error")
	_refresh_now()
	return r


## The full modal page of the same name (the Duty roster).
func full_page() -> void:
	if host != null and host.has_method("open_jobs"):
		host.open_jobs()


func _refresh_foot(s) -> void:
	var radio = _radio()
	var fw := {}
	if radio != null and radio.has_method("fill_willingness"):
		fw = radio.fill_willingness()
	var sig := "%s|%s" % [str(fw), str(_fill_report)]
	if sig == _foot_sig:
		return
	_foot_sig = sig
	var seats: Array = fw.get("seats", [])
	var free: Array = fw.get("free", [])
	var stuck: Array = fw.get("stuck", [])
	var seat_words: Array = []
	for e in seats:
		seat_words.append("%s %d" % [_station_name(String(e.station)), int(e.left)])
	var free_words: Array = []
	for id in free:
		var q = _person(String(id))
		free_words.append(String(q.first) if q != null else String(id))
	var tip := "Fill empty seats: the open seats go to people with no job, by skill. Nobody is taken off a job."
	var off := false
	if fw.is_empty():
		off = true
		tip = NO_RADIO
	elif seats.is_empty():
		off = true
		tip += "\nNot now: every seat has its crew."
	elif free.is_empty():
		off = true
		tip += "\nNot now: " + ("nobody without a job can take a seat." if not stuck.is_empty() else "everybody has a job.")
	if not fw.is_empty():
		tip += "\nOpen seats: %s" % (", ".join(seat_words) if not seat_words.is_empty() else "none")
		tip += "\nWith no job: %s" % (", ".join(free_words) if not free_words.is_empty() else "nobody")
		for e in stuck:
			tip += "\n%s" % _stuck_line(e)
	fill_button.disabled = off
	fill_button.tooltip_text = tip
	fill_button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if off else Control.CURSOR_POINTING_HAND
	_show_fill_report()


## "Hector is down": the reason of someone who could not be given a seat, with their name put in front when it has none.
func _stuck_line(e: Dictionary) -> String:
	var why := String(e.get("why", ""))
	var who := String(e.get("name", ""))
	if who != "" and not why.contains(who):
		return "%s: %s" % [who, why]
	return why


func _show_fill_report() -> void:
	for c in fill_box.get_children():
		fill_box.remove_child(c)
		c.queue_free()
	fill_box.visible = not _fill_report.is_empty()
	if _fill_report.is_empty():
		return
	var line := String(_fill_report.get("line", ""))
	if line != "":
		fill_box.add_child(_fill_label(line, host.OK if bool(_fill_report.get("ok", false)) else host.INK))
	for e in _fill_report.get("stuck", []):
		fill_box.add_child(_fill_label(_stuck_line(e), host.WARN))


func _fill_label(text: String, color: Color) -> Label:
	var l: Label = host._label(text, Fonts.sans(600), 13, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	return l


# ------------------------------------------------------------------ the stations --

func _toggle_stations() -> void:
	stations_box.visible = not stations_box.visible
	stations_toggle.text = "Hide station settings" if stations_box.visible else "Station settings"


## The sliders of the stations that have settings (the bench's ammo target and scrap reserve, the wall crew's threshold).
func _build_sliders() -> void:
	var s = _sim()
	if s == null or _sliders_built:
		return
	_sliders_built = true
	for st in _all_stations():
		if st.settings.is_empty():
			continue
		var id := String(st.id)
		var box: VBoxContainer = host._vbox(3)
		box.add_child(host._caps(String(st.name), host.INK2))
		sliders[id] = {}
		for key in st.settings:
			box.add_child(_setting(s, id, String(key), st.settings[key]))
		stations_box.add_child(box)


func _setting(s, station_id: String, key: String, def: Dictionary) -> Control:
	var box: VBoxContainer = host._vbox(0)
	var label: Label = host._label(String(def.get("label", key)), Fonts.sans(400), 13, host.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 60
	box.add_child(label)
	var line: HBoxContainer = host._hbox(8)
	var sl := HSlider.new()
	sl.min_value = float(def.min)
	sl.max_value = float(def.max)
	sl.step = float(def.step)
	sl.value = float(s.jobs.setting(station_id, key))
	sl.scrollable = false
	sl.focus_mode = Control.FOCUS_NONE
	sl.mouse_filter = Control.MOUSE_FILTER_PASS
	sl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sl.custom_minimum_size = Vector2(60, 22)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = "%s: drag to change it" % String(def.get("label", key))
	_style_slider(sl)
	line.add_child(sl)
	var value: Label = host._label(_value_text(def, sl.value), Fonts.cond(700), 14, host.INK)
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(value)
	box.add_child(line)
	sliders[station_id][key] = sl
	_value_labels["%s/%s" % [station_id, key]] = value
	sl.value_changed.connect(_on_setting.bind(station_id, key, def))
	return box


## A slider was moved: the jobs module keeps the value (inside its range and its steps) and the page shows what it kept.
func _on_setting(value: float, station_id: String, key: String, def: Dictionary) -> void:
	var s = _sim()
	if s == null:
		return
	s.jobs.set_setting(station_id, key, value)
	var now := float(s.jobs.setting(station_id, key))
	var sl: HSlider = sliders[station_id][key]
	if not is_equal_approx(sl.value, now):
		sl.set_value_no_signal(now)
	_value_labels["%s/%s" % [station_id, key]].text = _value_text(def, now)


func _refresh_sliders(s) -> void:
	for id in sliders:
		for key in sliders[id]:
			var sl: HSlider = sliders[id][key]
			var now := float(s.jobs.setting(String(id), String(key)))
			if not is_equal_approx(sl.value, now):
				sl.set_value_no_signal(now)
			var st: Dictionary = s.jobs.station(String(id))
			if st.has("settings") and st.settings.has(key):
				var text := _value_text(st.settings[key], now)
				var label: Label = _value_labels["%s/%s" % [id, key]]
				if label.text != text:
					label.text = text


## "300 ammo", "70%": a setting's value with its unit.
static func _value_text(def: Dictionary, value: float) -> String:
	var unit := String(def.get("unit", ""))
	if unit == "%":
		return "%d%%" % roundi(value)
	return "%d %s" % [roundi(value), unit] if unit != "" else "%d" % roundi(value)


func _style_slider(sl: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(host.INK, 0.2)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = host.BRASS
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	sl.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = host.BRASS.lightened(0.15)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	sl.add_theme_icon_override("grabber", MenuKit.disc(8, host.INK, host.OAK_DARK, 2.0))
	sl.add_theme_icon_override("grabber_highlight", MenuKit.disc(9, host.ACCENT, host.OAK_DARK, 2.0))
	sl.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# ------------------------------------------------------------------------ focus --

## Brings the eye to a person (their row is lit and in view; with no job the list of jobs opens for them) or to a station (a note
## says who holds it and how many seats are open, the rows of its crew are lit and its place is marked in the yard).
func focus_on(id: String) -> void:
	var s = _sim()
	if s == null or host == null or id == "":
		return
	var p = _person(id)
	if p != null and rows.has(id):
		_focus = {"kind": "person", "id": id}
		_focus_until = _now() + int(FOCUS_S * 1000.0)
		focus_note.visible = false
		_refresh_now()
		_scroll_to.call_deferred(rows[id].row)
		if String(s.jobs.job_of(p)) == "" and not _gone(p) and not _is_you(p) and not bool(_block(p).off):
			open_job_list(p)
		return
	var st: Dictionary = s.jobs.station(id)
	if st.is_empty():
		return
	_focus = {"kind": "station", "id": id}
	_focus_until = _now() + int(FOCUS_S * 1000.0)
	_refresh_now()
	show_marks(id)
	var sc := _outer_scroll()
	if sc != null:
		sc.scroll_vertical = 0


func _refresh_focus_note(s) -> void:
	var showing := not _focus.is_empty() and String(_focus.kind) == "station"
	focus_note.visible = showing
	if not showing:
		return
	var id := String(_focus.id)
	var st: Dictionary = s.jobs.station(id)
	var title := String(st.get("name", id))
	if bool(st.get("locked", false)):
		focus_note.text = "%s: not built yet." % title
		return
	var crew: Array = s.jobs.crew_of(id)
	var names: Array = []
	for q in crew:
		names.append(String(q.first))
	var holds := "nobody holds it" if names.is_empty() else ("%s %s it" % [" and ".join(names), "holds" if names.size() == 1 else "hold"])
	var open: int = int(s.jobs.seats_left(id))
	var seats := "no seat is open" if open <= 0 else ("%d seat%s open: use someone's Day button to give them the job" % [open, "" if open == 1 else "s"])
	var text := "%s: %s, %s." % [title, holds, seats]
	if focus_note.text != text:
		focus_note.text = text


## How tall the page would like to be: all its rows and the foot (the panel sizes itself to this, up to the room there is, and scrolls
## the rest).
func wanted_height() -> float:
	return get_combined_minimum_size().y if _built else 0.0
