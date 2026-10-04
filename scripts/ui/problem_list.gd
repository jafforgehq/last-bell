## The Trouble list (round 25, V25.2 PROBLEMS-VIEW of docs/superpowers/plans/2026-10-04-round-25.md): a compact list of the base's open problems, each
## with the time it has left, where the player deals with it. A row for each (`sim.problems.marks()`):
##
##   [glyph] Leak: 11 h left                 the rules' own words, the glyph and the colour of the marker in the yard (amber, red at stage 2)
##   [time bar]                              what is left of its time
##   Dez is on the way                       (when somebody has been sent, or "You are fixing it")
##   [Go there] [Ask Dez to fix it (72%)] [Someone else] [Keep them apart]
##   Dez: on it, about 20 seconds            the answer, for ANSWER_S seconds; a soft refusal in amber with [Insist]
##   [Ana  72%] [Marcus: tending a patient]  (Someone else) everyone at the base, each with `willing` or the reason
##
## Go there glides the camera to the marker (`host`'s meta "on_focus_problem", which main.gd sets to `focus_problem`, or `options.go`). Ask asks the
## person the rules would send (`problems.best_for`, or the one chosen below) through the radio, `radio.request_fix` (which hands it to the problems
## module): their answer and their refusal are the rules' words (`radio.reason_not` is the first of them: busy, hurt, down...), never the view's own;
## a refusal that is not a hard one offers Insist, at the usual cost of trust. Keep them apart is a quarrel's (`problems.separate`).
## Every control that is off says why in its tooltip. Nothing takes focus (the panel's buttons never do: W A S D and E keep working).
##
## A piece for a page to mount (the Base page's Trouble section; the same four functions as a radio panel page, `setup`, `refresh`, `focus_on`,
## `set_compact`):
##   var l := ProblemList.new(); parent.add_child(l)
##   l.setup(hud, func(): return sim)             # host: the HUD (lends its looks); the sim the list reads
##   l.refresh()                                  # with the page (10 Hz while it is open; the rows are kept, only their words change)
## The tests' hooks: `rows` (problem id to its controls), `ask(id, p)`, `insist(id)`, `go(id)`, `apart(id)`, `answers` (problem id to the last answer).
extends VBoxContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const BaseMarks := preload("res://scripts/render/base_marks.gd")

## How long the answer to a request stays under its row (real seconds).
const ANSWER_S := 6.0
const BAR_H := 8.0
const BUTTON_H := 28.0
const NOBODY_FREE := "Nobody is free to take it now. Pick someone below: a refusal that is not a hard one can be insisted on, at a cost of trust"
const EMPTY_TEXT := "No trouble now."


## The glyph of a kind, in the colour of its stage (the marker's own picture: BaseMarks.glyph).
class Glyph:
	extends Control
	var kind := "leak"
	var color := BaseMarks.AMBER

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 12.0, BaseMarks.PILL)
		draw_arc(c, 12.0, 0.0, TAU, 24, Color(color, 0.9), 1.5, true)
		BaseMarks.glyph(self, kind, c, 7.0, color)


## The time a problem has left: a thin bar that empties (the colour of its stage).
class TimeBar:
	extends Control
	var left := 1.0
	var color := BaseMarks.AMBER

	func _init() -> void:
		custom_minimum_size = Vector2(0, BAR_H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(left, 0.0, 1.0), size.y)), color)


var host
var sim_getter: Callable
var options := {}
## Problem id to its row's controls: {"panel", "glyph", "title", "bar", "status", "go", "ask", "more", "apart", "answer", "insist", "chips", "kind"}.
var rows := {}
## Problem id to the last answer it got: {"who", "first", "ok", "line", "why", "hard", "tone", "insisted", "chance", "at" (msec)}.
var answers := {}
## Problem id to the person the Ask is for when the player chose someone (an id), and whether the row's list of people is open.
var chosen := {}
var more_open := {}
var empty_label: Label
var compact := false
var _built := false
var _sig := ""
var _chips_sig := {}


func setup(host_hud: Object, getter: Callable, opts: Dictionary = {}) -> void:
	host = host_hud
	sim_getter = getter
	options = opts
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 6)
	empty_label = host._label(EMPTY_TEXT, Fonts.sans(400), 13, host.INK3)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(empty_label)


func set_compact(on: bool) -> void:
	if compact != on:
		compact = on
		refresh(true)


func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _radio():
	var s = _sim()
	return s.get("radio") if s != null else null


func _problems():
	var s = _sim()
	return s.get("problems") if s != null else null


## How many problems are listed.
func count() -> int:
	return rows.size()


## The list opens the row of this problem's people (what a click on a problem in the News or a "Details" button asks of a page).
func focus_on(id: String) -> void:
	if rows.has(id):
		more_open[id] = true
		refresh(true)


# ----------------------------------------------------------------- what is asked --

## The marks of the open problems as the rules give them (the sign of a quarantine is not trouble to fix: it is the dilemma's).
func _marks() -> Array:
	var out: Array = []
	var pm = _problems()
	if pm == null or not pm.has_method("marks"):
		return out
	var raw = pm.marks()
	if raw is Array:
		for m in raw:
			if m is Dictionary and String(m.get("id", "")) != "" and String(m.get("kind", "")) != "quarantine":
				out.append(m)
	return out


func _person(id: String):
	var s = _sim()
	if s == null:
		return null
	for p in s.people:
		if String(p.id) == id:
			return p
	return null


## Whether a person can be asked to do anything at all: at the base, up, not the one the player is.
func _askable(p) -> bool:
	return p != null and not p.dead and not p.turned and p.away == null and not bool(p.player)


## Who is at the base to be asked, in the crew's order.
func people() -> Array:
	var out: Array = []
	var s = _sim()
	if s == null:
		return out
	for p in s.people:
		if _askable(p):
			out.append(p)
	return out


## What the radio says of this person for this problem (`radio.fix_willingness`: {"ok", "why", "hard", "line", "tone", "delay_s", "chance", "cost", "eta_h"}).
func willingness(p, id: String) -> Dictionary:
	var radio = _radio()
	if radio != null and radio.has_method("fix_willingness"):
		return radio.fix_willingness(p, id)
	var pm = _problems()
	if pm != null and pm.has_method("fix_willingness"):
		return pm.fix_willingness(p, id)
	return {"ok": false, "why": "Nobody can be asked", "hard": true, "chance": 0.0}


## The person the Ask is for now: the one the player chose (while they can still be asked), else the one the rules would send. null for nobody.
func target(id: String):
	var chosen_id := String(chosen.get(id, ""))
	if chosen_id != "":
		var p = _person(chosen_id)
		if _askable(p):
			return p
		chosen.erase(id)
	var pm = _problems()
	if pm != null and pm.has_method("best_for"):
		var best = pm.best_for(id)
		if best != null and _askable(best):
			return best
	return null


## Whether somebody has been sent already: {"who": the person's first name, "state": "walking" | "working"}, {} when nobody, or when the avatar's own hands are at it.
func sent_of(id: String, m: Dictionary) -> Dictionary:
	var state := String(m.get("state", "idle"))
	if state != "walking" and state != "working":
		return {}
	var fixer := String(m.get("fixer", ""))
	if fixer == "" and not m.has("fixer"):
		var pm = _problems()
		var rec = pm.record(id) if pm != null and pm.has_method("record") else {}
		fixer = String(rec.get("fixer", "")) if rec is Dictionary else ""
	var p = _person(fixer) if fixer != "" else null
	return {"who": String(p.first) if p != null else "Somebody", "state": state}


## Whether the avatar's own hands are at this problem now.
func mine(id: String) -> bool:
	var pm = _problems()
	var fixing = pm.get("fixing") if pm != null else null
	return fixing is Dictionary and String(fixing.get("id", "")) == id and not (fixing as Dictionary).is_empty()


# ------------------------------------------------------------------- the acts --

## Asks `p` to go and fix problem `id` over the radio (what the Ask button does): the radio's answer, with the person added; it stays under the row for
## ANSWER_S seconds. {} with nobody to ask.
func ask(id: String, p, push: bool = false) -> Dictionary:
	var radio = _radio()
	if p == null or (radio == null and _problems() == null):
		return {}
	var args := {"insist": true} if push else {}
	var got = null
	if radio != null and radio.has_method("request_fix"):
		got = radio.request_fix(id, p, args)
	elif _problems() != null:
		got = _problems().request_fix(id, p, args)
	var res: Dictionary = (got as Dictionary).duplicate() if got is Dictionary else {"ok": false, "why": "Nobody answers", "hard": true}
	answers[id] = {"who": String(p.id), "first": String(p.first), "ok": bool(res.get("ok", false)), "line": String(res.get("line", "")),
		"why": String(res.get("why", "")), "hard": bool(res.get("hard", false)), "tone": String(res.get("tone", "")), "insisted": bool(res.get("insisted", false)),
		"chance": float(res.get("chance", 0.0)), "at": Time.get_ticks_msec()}
	chosen[id] = String(p.id)
	_play("ui_click" if bool(res.get("ok", false)) else "ui_error")
	refresh(true)
	return res


## Asks again the person who refused, pushing: a refusal that is not a hard one is overridden, at a cost of their trust and their mood.
func insist(id: String) -> Dictionary:
	var last: Dictionary = answers.get(id, {})
	if last.is_empty() or bool(last.ok):
		return {}
	return ask(id, _person(String(last.who)), true)


## The camera glides to the problem's marker (`main.focus_problem`). False when the host cannot (a stand-in) or there is no such problem.
func go(id: String) -> bool:
	var fn = options.get("go")
	if not (fn is Callable) and host != null and host.has_meta("on_focus_problem"):
		fn = host.get_meta("on_focus_problem")
	if fn is Callable and (fn as Callable).is_valid():
		return bool((fn as Callable).call(id))
	return false


## Keeps a quarrel's two apart (`problems.separate`): the rules' line, or their reason, under the row.
func apart(id: String) -> Dictionary:
	var pm = _problems()
	if pm == null or not pm.has_method("separate"):
		return {}
	var got = pm.separate(id)
	var res: Dictionary = (got as Dictionary).duplicate() if got is Dictionary else {}
	answers[id] = {"who": "", "first": "", "ok": bool(res.get("ok", false)), "line": String(res.get("line", "")), "why": String(res.get("why", "")),
		"hard": true, "tone": "", "insisted": false, "chance": 0.0, "at": Time.get_ticks_msec()}
	_play("ui_click" if bool(res.get("ok", false)) else "ui_error")
	refresh(true)
	return res


func _play(sound_name: String) -> void:
	if host != null and host.has_method("ui_sound"):
		host.ui_sound(sound_name, 0.5)


# ------------------------------------------------------------------- the rows --

## Brings the list in line with the game: a row for each open problem (made when it is new, taken away when it is gone), its words, its time, its
## buttons and the answer under it. Cheap when nothing changed: the rows are kept. `force` is for what the player just did.
func refresh(_force: bool = false) -> void:
	if not _built:
		return
	var list := _marks()
	var sig := ""
	for m in list:
		sig += "%s:%s;" % [String(m.id), String(m.kind)]
	if sig != _sig:
		_sig = sig
		for id in rows.keys():
			var gone := true
			for m in list:
				if String(m.id) == id:
					gone = false
			if gone:
				var panel: Control = rows[id].panel
				remove_child(panel)
				panel.queue_free()
				rows.erase(id)
				answers.erase(id)
				chosen.erase(id)
				more_open.erase(id)
				_chips_sig.erase(id)
		for m in list:
			if not rows.has(String(m.id)):
				var row := _make_row(m)
				rows[String(m.id)] = row
				add_child(row.panel)
	empty_label.visible = list.is_empty()
	for m in list:
		_update_row(String(m.id), m)


func _make_row(m: Dictionary) -> Dictionary:
	var id := String(m.id)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.24)
	sb.border_color = host.LINE2
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = host._vbox(5)
	panel.add_child(box)
	var head: HBoxContainer = host._hbox(8)
	var glyph := Glyph.new()
	glyph.kind = String(m.kind)
	head.add_child(glyph)
	var title: Label = host._label("", Fonts.sans(600), 14, host.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 40
	head.add_child(title)
	box.add_child(head)
	var bar := TimeBar.new()
	box.add_child(bar)
	var status: Label = host._label("", Fonts.sans(600), 13, host.OK)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 40
	box.add_child(status)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go_button := RadioKit.small_button(host, "Go there", BUTTON_H, 13)
	go_button.tooltip_text = "Go there: the camera glides to it, and comes back to you after a moment"
	go_button.pressed.connect(func(): go(id))
	buttons.add_child(go_button)
	var ask_button := RadioKit.small_button(host, "Ask", BUTTON_H, 13)
	ask_button.pressed.connect(func(): ask(id, target(id)))
	buttons.add_child(ask_button)
	var more_button := RadioKit.small_button(host, "Someone else", BUTTON_H, 13)
	more_button.pressed.connect(func():
		more_open[id] = not bool(more_open.get(id, false))
		refresh(true))
	buttons.add_child(more_button)
	var apart_button := RadioKit.small_button(host, "Keep them apart", BUTTON_H, 13)
	apart_button.tooltip_text = "Keep them apart: one of the two goes to another station, so they stop quarrelling. No roll, and nobody is pleased (mood -1 each)"
	apart_button.pressed.connect(func(): apart(id))
	apart_button.visible = String(m.kind) == "quarrel"
	buttons.add_child(apart_button)
	box.add_child(buttons)
	var answer_row: HBoxContainer = host._hbox(6)
	var answer: Label = host._label("", Fonts.sans(600), 13, host.INK)
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	answer.custom_minimum_size.x = 60
	answer_row.add_child(answer)
	var insist_button := RadioKit.small_button(host, "Insist", 26.0, 13)
	insist_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	insist_button.tooltip_text = "Insist: push them to do it anyway. It costs their trust and their mood, and they will do it grudgingly"
	insist_button.pressed.connect(func(): insist(id))
	answer_row.add_child(insist_button)
	answer_row.visible = false
	box.add_child(answer_row)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.visible = false
	box.add_child(chips)
	return {"panel": panel, "glyph": glyph, "title": title, "bar": bar, "status": status, "go": go_button, "ask": ask_button, "more": more_button,
		"apart": apart_button, "answer": answer, "answer_row": answer_row, "insist": insist_button, "chips": chips, "kind": String(m.kind)}


func _update_row(id: String, m: Dictionary) -> void:
	var r: Dictionary = rows[id]
	var stage := int(m.get("stage", 0))
	var pct := clampf(float(m.get("pct", 0.0)), 0.0, 1.0)
	var col: Color = BaseMarks.stage_color(stage, pct)
	var kind := String(m.kind)
	var text := String(m.get("label", ""))
	if text == "":
		text = BaseMarks.name_of(kind)
	_set_text(r.title, text)
	_ink(r.title, host.DANGER_TEXT if col == BaseMarks.RED else host.INK)
	var glyph: Glyph = r.glyph
	if glyph.color != col:
		glyph.color = col
		glyph.queue_redraw()
	var bar: TimeBar = r.bar
	if not is_equal_approx(bar.left, 1.0 - pct) or bar.color != col:
		bar.left = 1.0 - pct
		bar.color = col
		bar.queue_redraw()
	# who is on it
	var sent := sent_of(id, m)
	var status := ""
	if mine(id):
		status = "You are fixing it"
	elif not sent.is_empty():
		status = "%s is %s" % [String(sent.who), "on the way" if String(sent.state) == "walking" else "fixing it"]
	_set_text(r.status, status)
	(r.status as Label).visible = status != ""
	# the Ask: whoever the rules would send, or the one the player picked
	var who = target(id)
	var ask_b: Button = r.ask
	var tip := ""
	var disabled := false
	if status != "":
		disabled = true
		tip = "%s. Nobody else is needed" % status
	elif who == null:
		disabled = true
		_set_text(ask_b, "Ask someone")
		tip = NOBODY_FREE
		more_open[id] = bool(more_open.get(id, true))
	else:
		var w := willingness(who, id)
		var first := String(who.first)
		var chance := ""
		if bool(w.get("ok", false)):
			chance = " (%d%%)" % roundi(float(w.get("chance", 0.0)) * 100.0)
			tip = "%s: gets there in about %d s, %d%% to put it right%s" % [first, roundi(float(w.get("delay_s", 0.0))), roundi(float(w.get("chance", 0.0)) * 100.0), _cost_text(w)]
		else:
			disabled = bool(w.get("hard", false))
			tip = String(w.get("why", ""))
			if not disabled:
				tip += "\nAsk, and they will say so. Insist overrides it, at a cost of trust"
		_set_text(ask_b, ("Ask %s to fix it%s" % [first, chance]) if not compact else ("Ask %s%s" % [first, chance]))
	ask_b.disabled = disabled
	if ask_b.tooltip_text != tip:
		ask_b.tooltip_text = tip
	var more: Button = r.more
	var open := bool(more_open.get(id, false))
	_set_text(more, "Fewer" if open else "Someone else")
	more.tooltip_text = "Everyone at the base, with what each says to it"
	(r.apart as Button).visible = kind == "quarrel"
	# the answer
	var last: Dictionary = answers.get(id, {})
	if not last.is_empty() and float(Time.get_ticks_msec() - int(last.at)) / 1000.0 > ANSWER_S:
		answers.erase(id)
		last = {}
	var answer_row: Control = r.answer_row
	answer_row.visible = not last.is_empty()
	var insist_visible := false
	if not last.is_empty():
		var line := ""
		var ink: Color = host.INK
		if bool(last.ok):
			line = ("%s: %s" % [String(last.first), String(last.line)]) if String(last.first) != "" else String(last.line)
			ink = host.OK if String(last.tone) == "willing" else host.INK
		else:
			line = String(last.why)
			ink = host.WARN
			insist_visible = not bool(last.hard) and String(last.who) != ""
		_set_text(r.answer, line)
		_ink(r.answer, ink)
	(r.insist as Button).visible = insist_visible
	_update_chips(id, r, open)


## The people to choose from: a chip for each (their first name and `willing`, the chance, or the refusal): a tap asks them.
func _update_chips(id: String, r: Dictionary, open: bool) -> void:
	var flow: HFlowContainer = r.chips
	flow.visible = open
	if not open:
		_chips_sig.erase(id)
		return
	var who: Array = people()
	var stats: Array = []
	var sig := ""
	for p in who:
		var w := willingness(p, id)
		stats.append(w)
		sig += "%s|%s|%s|%s;" % [String(p.id), str(w.get("ok", false)), str(roundi(float(w.get("chance", 0.0)) * 100.0)), String(w.get("why", ""))]
	sig += String(chosen.get(id, ""))
	if String(_chips_sig.get(id, "")) == sig:
		return
	_chips_sig[id] = sig
	for c in flow.get_children():
		flow.remove_child(c)
		c.queue_free()
	if who.is_empty():
		var none: Label = host._label("Nobody else is at the base.", Fonts.sans(400), 13, host.INK3)
		flow.add_child(none)
		return
	for i in who.size():
		var p = who[i]
		var w: Dictionary = stats[i]
		var first := String(p.first)
		var b := RadioKit.small_button(host, "", 28.0, 13)
		if bool(w.get("ok", false)):
			b.text = "%s  %d%%" % [first, roundi(float(w.get("chance", 0.0)) * 100.0)]
			b.tooltip_text = "Ask %s: about %d s to get there, %d%% to put it right%s" % [first, roundi(float(w.get("delay_s", 0.0))), roundi(float(w.get("chance", 0.0)) * 100.0), _cost_text(w)]
		else:
			var why := String(w.get("why", ""))
			b.text = "%s: %s" % [first, _short_reason(first, why)]
			b.tooltip_text = why if bool(w.get("hard", false)) else "%s\nAsk, and they will say so. Insist overrides it, at a cost of trust" % why
			b.disabled = bool(w.get("hard", false))
			for state in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(state, host.WARN)
		if String(chosen.get(id, "")) == String(p.id):
			b.add_theme_color_override("font_color", host.ACCENT)
		b.pressed.connect(func(): ask(id, p))
		flow.add_child(b)


## "tending a patient" from "Ana: tending a patient"; "down" from "Dez is down".
static func _short_reason(first: String, why: String) -> String:
	for prefix in [first + ": ", first + " is ", first + " has ", first + " "]:
		if why.begins_with(prefix):
			return why.trim_prefix(prefix)
	return why


## ", costs 1 scrap" from the willingness's cost, "" when it costs nothing.
static func _cost_text(w: Dictionary) -> String:
	var cost = w.get("cost", {})
	if cost is Dictionary and float(cost.get("scrap", 0.0)) > 0.0:
		return ", costs %d scrap" % roundi(float(cost.scrap))
	return ""


func _set_text(c, text: String) -> void:
	if c.text != text:
		c.text = text


## Puts a label's ink on `color` when it is not already (a theme change is not free, and the list is refreshed ten times a second).
func _ink(label: Label, color: Color) -> void:
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)
