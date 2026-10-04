## The four policy dials (round 25, V25.1): Rations, Work hours, Scavenger boldness and Strangers at the gate, as the Base page shows them. Each dial is a slip
## with its name, two or three segmented buttons (the one that is set is filled gold), and under them what the option that is set costs and gives: the sim's
## own words (`policies.describe(dial, option)`: a blurb, the good things in green and the costs in amber). Pointing at another option shows ITS words in
## the same place ("If you choose Half rations"), and every option's words are its tooltip, so that a change is never a blind one: the sim lets a dial change
## once a game day.
##
## A press is the sim's `policies.set_dial(dial, option)`. What it answers is shown under the dial for a few seconds: the line of a change (green), or the
## reason of a refusal in the sim's own words ("Changed today: again tomorrow", amber): the view writes no reason of its own. A dial that was changed today
## says so beside its name (read from `policies.changed_day`), and its buttons stay pressable so that the refusal is the sim's. Nothing here takes focus
## (W A S D and E keep walking and using); with no policies module (an older fake, a game without the dials) every button is off and says why.
##
##   var d := PolicyDials.new(); page.add_child(d); d.setup(host, sim_getter)
##   d.choose("rations", "half")   # -> the sim's {"ok", "line", "why"}
##   d.refresh()                   # each refresh of the page: cheap, a dial is redrawn only when what it shows changed
extends VBoxContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")

## The dials in the order they are shown, what each is called, and what it is (its title's tooltip). (The sim's `policies.OPTIONS` says which options a
## dial has; these are for a stand-in that has none.)
const DIALS := ["rations", "hours", "boldness", "strangers"]
const DIAL_NAMES := {"rations": "Rations", "hours": "Work hours", "boldness": "Scavenger boldness", "strangers": "Strangers at the gate"}
const DIAL_TIPS := {
	"rations": "How much everyone eats and drinks: the stores last longer, and so does the grumbling",
	"hours": "How hard the crew works: more done, and the weary wear out",
	"boldness": "How far the parties you ask to go out will risk: more loot, and more lost",
	"strangers": "What the base does about people who call at the gate",
}
const OPTION_FALLBACK := {
	"rations": ["full", "half", "hungry"], "hours": ["normal", "overtime"], "boldness": ["careful", "usual", "bold"], "strangers": ["let_in", "check", "turn_away"],
}
## How long an answer stays under its dial (seconds).
const ANSWER_S := 6.0
## The weariness a person is "worn out" at (the sim's `WORN_AT` when it has one).
const WORN_AT := 60.0
const OFF := "The dials are not in this game"
const SLIP_BG := Color("#22362f")
const SLIP_EDGE := Color(0.93, 0.96, 0.89, 0.16)

var host
var sim_getter: Callable
## dial -> {option id -> Button}; the answer's label, the words under the dial and the "changed today" tag, by dial.
var buttons := {}
var answers := {}
var words := {}
var tags := {}
## dial -> the option the pointer is on ("" when none): its words are the ones shown.
var previews := {}
var _slips := {}
var _head_labels := {}
var _note_rows := {}
var _extra := {}
var _sig := {}
var _built := false
var _answers := {}
var _skipped := 0


func setup(p_host, p_sim_getter: Callable) -> void:
	host = p_host
	sim_getter = p_sim_getter
	if _built:
		refresh()
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("separation", 6)
	for dial in DIALS:
		add_child(_make_dial(String(dial)))
	refresh()


func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _module():
	var s = _sim()
	var m = s.get("policies") if s != null else null
	return m if m != null and m.has_method("set_dial") else null


func _now() -> int:
	return Time.get_ticks_msec() + _skipped


## Moves the view's clock on (tests: the answers' time).
func skip_ahead(ms: int) -> void:
	_skipped += ms


# ------------------------------------------------------------------- reading --

## The dials, in the order they are shown.
func dials() -> Array:
	return DIALS.duplicate()


## The options of a dial (the sim's `OPTIONS`, or the contract's).
func options_of(dial: String) -> Array:
	var raw = RadioKit.rule_of(_module(), "OPTIONS", OPTION_FALLBACK)
	var opts = (raw as Dictionary).get(dial, OPTION_FALLBACK.get(dial, [])) if raw is Dictionary else OPTION_FALLBACK.get(dial, [])
	return (opts as Array).duplicate() if opts is Array else []


## The option that is set now ("" with no module).
func current_of(dial: String) -> String:
	var m = _module()
	var cur = m.get("current") if m != null else null
	if cur is Dictionary and (cur as Dictionary).has(dial):
		return String(cur[dial])
	var def = RadioKit.rule_of(m, "DEFAULTS", {})
	return String((def as Dictionary).get(dial, "")) if def is Dictionary else ""


## What the sim says of an option: {"name", "blurb", "pros", "cons"} (empty words with no module).
func describe(dial: String, option: String) -> Dictionary:
	var m = _module()
	var d = m.describe(dial, option) if m != null and m.has_method("describe") else null
	var out := {"name": "", "blurb": "", "pros": [], "cons": []}
	if d is Dictionary:
		out.name = String(d.get("name", ""))
		out.blurb = String(d.get("blurb", ""))
		for key in ["pros", "cons"]:
			var raw = d.get(key, [])
			if raw is Array:
				for line in raw:
					if String(line).strip_edges() != "":
						out[key].append(String(line).strip_edges())
	if String(out.name) == "":
		out.name = option.replace("_", " ").capitalize()
	return out


## Whether the dial was changed today: the sim's own word for it when it has one (`why_locked`), else the day it was last changed (`changed_day`).
func locked_today(dial: String) -> bool:
	var m = _module()
	var s = _sim()
	if m == null or s == null:
		return false
	if m.has_method("why_locked"):
		return String(m.why_locked(dial)) != ""
	var cd = m.get("changed_day")
	return cd is Dictionary and (cd as Dictionary).has(dial) and int((cd as Dictionary)[dial]) >= int(s.day)


## The words shown under a dial: the preview's when the pointer is on another option, else the set one's.
func consequence_text(dial: String) -> String:
	var opt := String(previews.get(dial, ""))
	if opt == "":
		opt = current_of(dial)
	var d := describe(dial, opt)
	var parts: Array = []
	if String(d.blurb) != "":
		parts.append(String(d.blurb))
	for l in d.pros:
		parts.append("+ %s" % String(l))
	for l in d.cons:
		parts.append("- %s" % String(l))
	return "\n".join(parts)


## Who is worn out now (first names, the most weary first), for the hours dial: the sim's own `worn_out()` (ids) when it has one, else the weariness it
## keeps (`weary`, from WORN_AT up).
func worn_out() -> Array:
	var m = _module()
	var s = _sim()
	var out: Array = []
	if m == null or s == null:
		return out
	var ids: Array = []
	if m.has_method("worn_out"):
		var raw = m.worn_out()
		if raw is Array:
			ids = raw
	else:
		var weary = m.get("weary")
		if weary is Dictionary:
			for id in weary:
				if float(weary[id]) >= WORN_AT:
					ids.append(String(id))
	for id in ids:
		for p in s.people:
			if String(p.id) == String(id) and not p.dead:
				out.append(String(p.first))
	return out


## What the dial is called: the sim's own title ("Scavengers"), else ours.
func title_of(dial: String) -> String:
	var m = _module()
	if m != null and m.has_method("title"):
		var t := String(m.title(dial)).strip_edges()
		if t != "":
			return t
	return String(DIAL_NAMES.get(dial, dial.capitalize()))


# -------------------------------------------------------------------- building --

func _slip_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = SLIP_BG
	st.border_color = SLIP_EDGE
	st.set_border_width_all(1)
	st.set_corner_radius_all(5)
	st.anti_aliasing = true
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 7
	return st


func _make_dial(dial: String) -> Control:
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_PASS
	slip.add_theme_stylebox_override("panel", _slip_style())
	var col: VBoxContainer = host._vbox(4)
	slip.add_child(col)
	var head: HBoxContainer = host._hbox(6)
	var title: Label = host._label(title_of(dial).to_upper(), Fonts.cond(700, 1), 12, host.INK2)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.tooltip_text = String(DIAL_TIPS.get(dial, ""))
	head.add_child(title)
	head.add_child(host._spacer())
	var tag: Label = host._label("", Fonts.sans(600), 12, host.WARN)
	tag.visible = false
	head.add_child(tag)
	col.add_child(head)
	var row: HBoxContainer = host._hbox(4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	buttons[dial] = {}
	for option in options_of(dial):
		var b := RadioKit.small_button(host, String(option).capitalize(), 28.0, 13)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0.0
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.set_meta("lit", false)
		b.pressed.connect(choose.bind(dial, String(option)))
		b.mouse_entered.connect(_on_hover.bind(dial, String(option), true))
		b.mouse_exited.connect(_on_hover.bind(dial, String(option), false))
		row.add_child(b)
		buttons[dial][String(option)] = b
	col.add_child(row)
	var text: Label = host._label("", Fonts.sans(400), 12, host.INK2)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 60
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.visible = false
	col.add_child(text)
	var pros: VBoxContainer = host._vbox(1)
	col.add_child(pros)
	var extra: Label = host._label("", Fonts.sans(600), 12, host.INK2)
	extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	extra.custom_minimum_size.x = 60
	extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	extra.visible = false
	col.add_child(extra)
	var answer: Label = host._label("", Fonts.sans(600), 12, host.OK)
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer.custom_minimum_size.x = 60
	answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer.visible = false
	col.add_child(answer)
	tags[dial] = tag
	words[dial] = text
	answers[dial] = answer
	_extra[dial] = extra
	_note_rows[dial] = pros
	_head_labels[dial] = title
	_slips[dial] = slip
	return slip


func _on_hover(dial: String, option: String, on: bool) -> void:
	if on:
		previews[dial] = option
	elif String(previews.get(dial, "")) == option:
		previews[dial] = ""
	_sig.erase(dial)
	_refresh_dial(dial)


# --------------------------------------------------------------------- refreshing --

func refresh() -> void:
	if not _built:
		return
	for dial in DIALS:
		_refresh_dial(String(dial))


func _refresh_dial(dial: String) -> void:
	var m = _module()
	var cur := current_of(dial)
	var preview := String(previews.get(dial, ""))
	var locked := locked_today(dial)
	var worn := worn_out() if dial == "hours" else []
	var note: Dictionary = _answers.get(dial, {})
	var live := not note.is_empty() and _now() < int(note.until)
	var sig := "%s|%s|%s|%s|%s|%s|%s" % [str(m != null), cur, preview, str(locked), str(worn), str(note.get("text", "")) if live else "", consequence_text(dial)]
	if _sig.get(dial, "") == sig:
		return
	_sig[dial] = sig
	var heading := title_of(dial).to_upper()
	if _head_labels[dial].text != heading:
		_head_labels[dial].text = heading
	var tag: Label = tags[dial]
	tag.text = "Changed today: again tomorrow" if locked else ""
	tag.visible = locked
	for option in buttons[dial]:
		var b: Button = buttons[dial][option]
		var d := describe(dial, String(option))
		var on := String(option) == cur and m != null
		if b.text != String(d.name):
			b.text = String(d.name)
		if bool(b.get_meta("lit")) != on:
			b.set_meta("lit", on)
			_style_option(b, on)
		b.disabled = m == null
		var lines: Array = [String(d.name)]
		if String(d.blurb) != "":
			lines.append(String(d.blurb))
		for l in d.pros:
			lines.append("+ %s" % String(l))
		for l in d.cons:
			lines.append("- %s" % String(l))
		if m == null:
			lines = [OFF]
		elif on:
			lines.append("Set now.")
		var want := "\n".join(lines)
		if b.tooltip_text != want:
			b.tooltip_text = want
	# the words under the dial: the set option's, or the one the pointer is on (headed by what it is)
	var shown := preview if preview != "" else cur
	var d := describe(dial, shown)
	var blurb: Label = words[dial]
	var head := ""
	if preview != "" and preview != cur:
		head = "If you choose %s: " % String(d.name)
	var blurb_text := ("%s%s" % [head, String(d.blurb)]).strip_edges()
	blurb.text = blurb_text if m != null else OFF
	blurb.visible = blurb.text != ""
	var box: VBoxContainer = _note_rows[dial]
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if m != null:
		for l in d.pros:
			box.add_child(_line("+ %s" % String(l), host.OK))
		for l in d.cons:
			box.add_child(_line("- %s" % String(l), host.WARN))
	var extra: Label = _extra[dial]
	if dial == "hours" and not worn.is_empty():
		extra.text = "Worn out now: %s" % ", ".join(worn)
		extra.visible = true
	else:
		extra.visible = false
	var answer: Label = answers[dial]
	if live:
		answer.text = String(note.text)
		answer.add_theme_color_override("font_color", host.OK if bool(note.ok) else host.WARN)
		answer.visible = true
	else:
		answer.visible = false
		if not note.is_empty():
			_answers.erase(dial)


func _line(text: String, ink: Color) -> Label:
	var l: Label = host._label(text, Fonts.sans(600), 12, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _style_option(b: Button, on: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st: StyleBox = host._button_style(state, on, false, false)
		st.content_margin_top = 0
		st.content_margin_bottom = 0
		st.content_margin_left = 6
		st.content_margin_right = 6
		b.add_theme_stylebox_override(state, st)
	var ink: Color = host.ACCENT_INK if on else host.INK
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	b.add_theme_color_override("font_disabled_color", Color(host.ACCENT, 0.9) if on else host.INK3)


# ------------------------------------------------------------------------ acting --

## Sets a dial as the sim takes it: its own {"ok", "line", "why"}. What it says is under the dial for ANSWER_S seconds: the line of a change in green, the
## reason of a refusal in amber. Pressing the option that is set does nothing ({"ok": true, "same": true}); without the module there is nothing to ask.
func choose(dial: String, option: String) -> Dictionary:
	var m = _module()
	if m == null:
		return {"ok": false, "line": "", "why": OFF}
	if option == current_of(dial):
		return {"ok": true, "line": "", "why": "", "same": true}
	var got = m.set_dial(dial, option)
	var r: Dictionary = got if got is Dictionary else {"ok": false, "line": "", "why": ""}
	var ok := bool(r.get("ok", false))
	var say := String(r.get("line", "")) if ok else String(r.get("why", ""))
	if not ok and say == "":
		say = "That cannot be changed now"
	if say != "":
		_answers[dial] = {"text": say, "ok": ok, "until": _now() + int(ANSWER_S * 1000.0)}
	if host != null and host.has_method("ui_sound"):
		host.ui_sound("ui_confirm" if ok else "ui_error")
	_sig.erase(dial)
	_refresh_dial(dial)
	return r


## The answer under a dial now ("" when none): {"text", "ok"}.
func answer_of(dial: String) -> Dictionary:
	var note: Dictionary = _answers.get(dial, {})
	if note.is_empty() or _now() >= int(note.until):
		return {}
	return {"text": String(note.text), "ok": bool(note.ok)}
