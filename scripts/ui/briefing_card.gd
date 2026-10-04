## The briefing card (round 25, V25.1): the morning briefing as a slim board at the top of the window, under the crew bar, where the dawn card sits. It
## says what the base is worried about, ranked (the top three lines, two in a small window), each with an icon in the colour of its level, and asks the one
## question that matters: what comes first today. Six chips (priority_kit.gd) set up to four priorities in the order they are tapped (the sim's
## `priorities.toggle`), **Use these** sets the two the top concerns point at (`priorities.set_order`), **Details** opens the Base page, and **Fine, carry on**
## puts the card away. Until the player taps, nothing changes: the jobs stay as they are.
##
## It is NOT a modal: the game goes on under it (it never touches the speed), it takes no key (every control is FOCUS_NONE: W A S D and E keep walking and
## using), and it blocks nothing but the pixels it covers (the panel stops the mouse so a click on it is not a shot). It is up for SECONDS of real time,
## but while the pointer is on it the clock waits; a chip tap leaves it a few more seconds to tap the next (CHIP_GRACE), and it goes at once when four are
## ranked or Details or Fine, carry on is pressed. Esc puts it away (main.gd: the talk card, then this card, then the radio panel...).
##
## The HUD owns it (hud.gd, the last section: `show_briefing()`, `briefing_open()`, `close_briefing()`, the anchor `briefing`). `data` is what the sim's
## `briefing.compose()` made, {"day", "lines": [concern], "order", "suggested"}; a line is a concern ({"id", "level", "text", "sub", "page", "focus"}).
## It borrows the HUD's looks (`host.PANEL`, `host._label()`...) and reads the sim only through `sim.priorities`.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const PriorityKit := preload("res://scripts/ui/priority_kit.gd")
const DawnCard := preload("res://scripts/ui/dawn_card.gd")

## Emitted once, when the card is gone. `why`: "dismiss", "esc", "details", "done" (four ranked), "use" (Use these), "timeout", "gone".
signal closed(why: String)

## How long it stays, how long it takes to fade at the end, and how long it waits after a chip is tapped (real seconds).
const SECONDS := 25.0
const FADE := 0.6
const CHIP_GRACE := 6.0
const MIN_W := 290.0
const MAX_W := 400.0
const MARGIN := 12.0
## How many lines of the concerns it shows, and in a small window.
const LINES := 3
const LINES_COMPACT := 2

var host
var data := {}
var panel: PanelContainer
## The lines shown (the concerns as the sim gave them) and their rows.
var lines: Array = []
var rows: Array = []
var chips := {}
var title_label: Label
var caps_label: Label
var hint_label: Label
var feedback_label: Label
var use_button: Button
var details_button: Button
var dismiss_button: Button
## Why it closed ("" while it is up), for the tests.
var close_reason := ""
var _body: VBoxContainer
var _rows_box: VBoxContainer
var _open := true
var _left := SECONDS
var _hovered := false
var _compact := false
var _squeezed := false
var _passes := 3
var _feedback_left := 0.0
var _sync_t := 0.0
var _chip_sig := ""
var _rp_sig := ""
var _sim_getter: Callable


func setup(h, d: Dictionary, sim_getter: Callable = Callable()) -> void:
	host = h
	data = d
	_sim_getter = sim_getter
	_compact = bool(host.get("compact"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	panel = host._panel(host._style(host.PANEL, 6, host.LINE, true, "panel_slim"))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_entered.connect(func(): _hovered = true)
	panel.mouse_exited.connect(func(): _hovered = false)
	add_child(panel)
	_body = host._vbox(6)
	panel.add_child(_body)
	_build()
	resized.connect(func(): _layout(_passes == 0))
	_layout(false)
	_passes = 3
	if host.has_method("ui_sound"):
		host.ui_sound("ui_open", 0.6)


func _sim():
	if _sim_getter.is_valid():
		return _sim_getter.call()
	return host.get("sim_ref") if host != null else null


# ------------------------------------------------------------------------- build --

func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	rows.clear()
	lines.clear()
	_squeezed = false
	var head: VBoxContainer = host._vbox(0)
	caps_label = host._caps("Briefing")
	head.add_child(caps_label)
	title_label = host._label("Morning, day %d" % int(data.get("day", 1)), Fonts.cond(700), 22, host.INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 120
	head.add_child(title_label)
	_body.add_child(head)
	# the top concerns, ranked
	_rows_box = host._vbox(4)
	_body.add_child(_rows_box)
	var raw = data.get("lines", [])
	var most := LINES_COMPACT if _compact else LINES
	if raw is Array:
		for l in raw:
			if lines.size() >= most:
				break
			if l is Dictionary and String(l.get("text", "")).strip_edges() != "":
				lines.append(l)
	for l in lines:
		_add_line(l)
	if lines.is_empty():
		_rows_box.add_child(_para("Nothing is wrong that anyone has noticed.", 13, host.INK2))
	# the question
	hint_label = _para("", 12, host.INK3)
	_body.add_child(hint_label)
	var made := PriorityKit.make(host, _on_chip, PriorityKit.ids_of(_sim()))
	chips = made.chips
	_body.add_child(made.flow)
	feedback_label = _para("", 12, host.WARN)
	feedback_label.visible = false
	_body.add_child(feedback_label)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 4)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	use_button = _button("Use these", true)
	use_button.pressed.connect(use_these)
	buttons.add_child(use_button)
	details_button = _button("Details", false)
	details_button.tooltip_text = "Open the Base page: the priorities with what they do, the dials, the facilities\nKey: B"
	details_button.pressed.connect(details)
	buttons.add_child(details_button)
	dismiss_button = _button("Fine, carry on", false)
	dismiss_button.tooltip_text = "Put the briefing away: nothing changes, the jobs stay as they are\nKey: Esc"
	dismiss_button.pressed.connect(dismiss)
	buttons.add_child(dismiss_button)
	_body.add_child(buttons)
	_sync()


func _para(text: String, size_px: int, ink: Color, weight: int = 400) -> Label:
	var l: Label = host._label(text, Fonts.sans(weight), size_px, ink)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, primary: bool) -> Button:
	var b := RadioKit.small_button(host, text, 30.0, 13)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.x = 64.0
	if primary:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var st: StyleBox = host._button_style(state, true, false, false)
			st.content_margin_top = 0
			st.content_margin_bottom = 0
			st.content_margin_left = 10
			st.content_margin_right = 10
			b.add_theme_stylebox_override(state, st)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, host.ACCENT_INK)
		b.add_theme_color_override("font_disabled_color", Color(host.ACCENT, 0.9))
	return b


## One ranked line: its rank, its icon in the colour of its level, its words and (in a roomy card) what is under them.
func _add_line(l: Dictionary) -> void:
	var level := String(l.get("level", "info"))
	var tone: Color = RadioKit.level_color(host, level)
	var row: HBoxContainer = host._hbox(7)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 1)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: TextureRect = host._icon(RadioKit.concern_icon(String(l.get("id", "")), level), 16, tone)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pad.add_child(icon)
	row.add_child(pad)
	var col: VBoxContainer = host._vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text: Label = host._label(String(l.get("text", "")), Fonts.sans(600), 14, tone)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 120
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(text)
	var sub := String(l.get("sub", "")).strip_edges()
	if sub != "":
		var s: Label = host._label(sub, Fonts.sans(400), 12, host.INK2)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 120
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.set_meta("sub", true)
		col.add_child(s)
	row.add_child(col)
	_rows_box.add_child(row)
	rows.append(row)


## The words of the lines the card shows, in order (for the tests).
func line_texts() -> Array:
	var out: Array = []
	for l in lines:
		out.append(String(l.get("text", "")))
	return out


# ---------------------------------------------------------------------- the chips --

func _on_chip(id: String) -> void:
	tap(id)


## A tap on a chip: the sim's `priorities.toggle` (the rank is the tap order). A refusal (a fifth) is said under the chips in the sim's words. The card
## waits a few seconds for the next tap and goes when four are ranked. {"ok", "why"}.
func tap(id: String) -> Dictionary:
	var r := PriorityKit.tap(_sim(), id)
	if bool(r.get("ok", false)):
		_left = minf(_left, CHIP_GRACE)
		_say("")
	else:
		_say(String(r.get("why", "")))
	_sync()
	if bool(r.get("ok", false)) and PriorityKit.order_of(_sim()).size() >= PriorityKit.max_set(_sim()):
		close("done")
	return r


## "Use these": the two priorities the top concerns point at, set in one tap. {"ok", "why"}.
func use_these() -> Dictionary:
	var r := PriorityKit.use_suggested(_sim())
	if bool(r.get("ok", false)):
		_sync()
		close("use")
	else:
		_say(String(r.get("why", "")))
	return r


## Details: the Base page of the radio panel, on its priorities; the card has done its part.
func details() -> void:
	if host != null and host.has_method("open_radio"):
		host.open_radio("base", {"focus": "priorities"})
	close("details")


func dismiss() -> void:
	close("dismiss")


func _say(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = text != ""
	_feedback_left = 5.0 if text != "" else 0.0


## The chips, the suggestion and the buttons, brought up to date with the sim.
func _sync() -> void:
	var sim = _sim()
	PriorityKit.sync(host, chips, sim)
	var suggested := PriorityKit.suggested_of(sim)
	var order := PriorityKit.order_of(sim)
	var sig := "%s|%s" % [str(suggested), str(order)]
	if sig == _chip_sig:
		return
	_chip_sig = sig
	if suggested.is_empty():
		hint_label.text = "What comes first today? Tap up to four, in order."
	else:
		hint_label.text = "Suggested: %s. Or tap up to four, in order." % PriorityKit.words_of(suggested)
	use_button.disabled = suggested.is_empty() or suggested == order
	if suggested.is_empty():
		use_button.tooltip_text = "Nothing to suggest right now: tap the chips yourself"
	elif suggested == order:
		use_button.tooltip_text = "These are your priorities already"
	else:
		use_button.tooltip_text = "Set %s as your priorities: the first counts most" % PriorityKit.words_of(suggested)
	_passes = 3


# ------------------------------------------------------------------------ layout --

## The window is small: two lines, and in a tight corner no sub lines.
func set_compact(on: bool) -> void:
	if on != _compact:
		_compact = on
		_build()
		_passes = 3


## Where the card goes: at the top, under the crew bar and under the dawn card when that is up, between the stores and the clock, as wide as the room
## allows; clear of the selection dock (to its right, or with fewer words) when the window is short.
func _layout(shrink: bool = true) -> void:
	if panel == null or not is_inside_tree():
		return
	var origin := get_global_rect().position
	var top := MARGIN
	var bar = host.get("bar")
	if bar is Control and bar.is_visible_in_tree() and bar.get_global_rect().position.y - origin.y < size.y * 0.5:
		top = bar.get_global_rect().end.y - origin.y + 8.0
	for c in host.get_children():
		if c is Control and c != self and c.visible and c.get_script() == DawnCard:
			var panel_of = c.get("panel")
			if panel_of is Control and panel_of.is_visible_in_tree():
				top = maxf(top, panel_of.get_global_rect().end.y - origin.y + 8.0)
	var lo := MARGIN
	var hi := size.x - MARGIN
	var col = host.get("left_col")
	if col is Control and col.is_visible_in_tree():
		var r := Rect2(col.get_global_rect().position - origin, col.get_global_rect().size)
		if r.size.x > 1.0 and r.end.y > top - 4.0:
			lo = maxf(lo, r.end.x + 8.0)
	var right = host.get("right_col")
	if right is Control and right.is_visible_in_tree():
		var r2 := Rect2(right.get_global_rect().position - origin, right.get_global_rect().size)
		if r2.size.x > 1.0 and r2.end.y > top - 4.0:
			hi = minf(hi, r2.position.x - 8.0)
	var rp = host.get("radio_panel")    # (the radio panel is up at the right: the card keeps to its left)
	if rp is Control and rp.is_visible_in_tree():
		var r3 := Rect2(rp.get_global_rect().position - origin, rp.get_global_rect().size)
		if r3.size.x > 1.0 and r3.end.y > top - 4.0:
			hi = minf(hi, r3.position.x - 8.0)
	var width := clampf(minf(MAX_W, hi - lo), 200.0, MAX_W)
	var x := clampf((size.x - width) / 2.0, lo, maxf(lo, hi - width))
	panel.custom_minimum_size.x = width
	panel.size = Vector2(width, 0.0)
	panel.reset_size()
	panel.size = Vector2(width, 0.0)
	var guard := 0
	while guard < 8:
		guard += 1
		var h := panel.get_combined_minimum_size().y
		var dock := _dock_rect(origin)
		var bottom := size.y - MARGIN
		var clash := dock.size != Vector2.ZERO and Rect2(Vector2(x, top), Vector2(width, h)).intersects(dock)
		if not clash and top + h <= bottom:
			break
		if clash and dock.end.x + 8.0 + width <= hi and x < dock.end.x + 8.0:
			x = dock.end.x + 8.0
			continue
		if not shrink or not _shrink_step():
			break
		panel.reset_size()
	panel.position = Vector2(x, top)
	panel.size = Vector2(width, panel.get_combined_minimum_size().y)


func _dock_rect(origin: Vector2) -> Rect2:
	var dock = host.get("dock")
	var inspect = host.get("inspect")
	if dock is Control and inspect is Control and inspect.is_visible_in_tree() and dock.is_visible_in_tree():
		var r: Rect2 = dock.get_global_rect()
		return Rect2(r.position - origin, r.size).grow(6.0)
	return Rect2()


## One step to make the card smaller: the caption, the hint and the sub lines go; then the concerns beyond the first.
func _shrink_step() -> bool:
	if not _squeezed:
		_squeezed = true
		caps_label.visible = false
		hint_label.visible = false
		for row in rows:
			for c in row.get_child(1).get_children():
				if c is Label and bool(c.get_meta("sub", false)):
					c.visible = false
		return true
	if rows.size() > 1:
		var row = rows.pop_back()
		_rows_box.remove_child(row)
		row.queue_free()
		lines.pop_back()
		return true
	return false


# ----------------------------------------------------------------------- closing --

func _process(dt: float) -> void:
	tick(dt)


## Time passes (real seconds): the card is re-laid out for a moment after it is built, its chips follow the sim, and it goes when its time is up (the
## clock waits while the pointer is on it).
func tick(dt: float) -> void:
	if not _open:
		return
	# (the radio panel opens, shuts or is resized: the card keeps to its left)
	var rp = host.get("radio_panel")
	var rp_sig := str(rp.get_global_rect()) if rp is Control and rp.is_visible_in_tree() else ""
	if rp_sig != _rp_sig:
		_rp_sig = rp_sig
		_passes = maxi(_passes, 2)
	if _passes > 0:
		_passes -= 1
		_layout(_passes == 0)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 0.2
		_sync()
	if _feedback_left > 0.0:
		_feedback_left -= dt
		if _feedback_left <= 0.0:
			_say("")
	if not _hovered:
		_left -= dt
	if _left <= 0.0:
		close("timeout")
		return
	if _left < FADE and not Prefs.on("ui", "reduce_motion"):
		modulate.a = clampf(_left / FADE, 0.0, 1.0)
	elif modulate.a < 1.0:
		modulate.a = 1.0


func is_open() -> bool:
	return _open


func seconds_left() -> float:
	return _left


## Puts the card away. (`why`: "esc" from the Esc key, the others as `closed` has them.)
func close(why: String = "dismiss") -> void:
	if not _open:
		return
	_open = false
	close_reason = why
	set_process(false)
	hide()
	closed.emit(why)
	queue_free()
