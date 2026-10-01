## The dawn assembly: a card of notebook paper on the HUD that tells the story of the night in a
## few ruled lines (how many were put down and by whom, the wall, who was lost and what is said of
## them, what was learned, the day's news, the mood of the crew). It does NOT pause the game and
## blocks nobody: it sits at the top under the crew, between the stores and the clock (clear of the
## selection dock where the window lets it), stays 15 seconds (real time) or until it is clicked or
## any key is pressed (the key still goes to the game), and Esc puts it away. The alert `dawn`
## opens it again.
##
## It reads the storyteller's `report()`; it borrows the HUD's styles, colours and icons.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")

## Emitted once, when the card is gone.
signal closed

## How long it stays, and how long it takes to fade out at the end (real seconds).
const SECONDS := 15.0
const FADE := 0.6
## The card's width (it is narrower in a narrow window) and its distance from the window's edge.
const MIN_W := 280.0
const MAX_W := 380.0
const MARGIN := 12.0
## The rows that can be dropped (last first) when the window is too short for all of them.
const MOST_EVENTS := 3
const MOST_LOST := 3

var hud
var report := {}
var panel: PanelContainer
var rows: Array = []
## Rows by what they are about: "kills", "wall", "lost", "hurt", "skills", "event", "mood".
var row_kinds: Array = []
var _body: VBoxContainer
var _caps: Label
var _title: Label
var _tip: Label
var _squeezed := false
## Frames left in which the card lays itself out again (wrapped words only know their height once they
## have a width, and a panel does not shrink by itself).
var _passes := 3
var _t := 0.0
var _seconds := SECONDS
var _open := true
var _dropped := 0


func setup(h, rep: Dictionary, seconds: float = SECONDS) -> void:
	hud = h
	report = rep
	_seconds = seconds
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = hud._panel(hud._paper_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(_on_panel_input)
	panel.tooltip_text = "Click to put it away. The alert brings it back."
	add_child(panel)
	_body = hud._vbox(7)
	panel.add_child(_body)
	_build()
	resized.connect(func(): _layout(_passes == 0))
	_layout(false)
	_passes = 3


# ------------------------------------------------------------------------- build --

func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	rows.clear()
	row_kinds.clear()
	var head: VBoxContainer = hud._vbox(0)
	_caps = hud._caps("Morning assembly", hud.PAPER_INK3)
	head.add_child(_caps)
	_title = hud._label("Night %d is over" % int(report.get("night", 0)), Fonts.cond(700), 24, hud.PAPER_INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 160
	head.add_child(_title)
	_body.add_child(head)
	_squeezed = false

	var kills := int(report.get("kills", 0))
	var mvp: Dictionary = report.get("mvp", {})
	var line := "%d put down" % kills if kills > 0 else "Nobody put down: a quiet night"
	if kills > 0 and not mvp.is_empty():
		line += ", most by %s (%d)" % [String(mvp.get("who", "")), int(mvp.get("kills", 0))]
	_row("kills", "walker", line)

	var lost_hp := int(report.get("wall_lost", 0))
	var mended := int(report.get("wall_mended", 0))
	var wall := "The wall held: nothing lost" if lost_hp <= 0 else "Wall: %d health lost" % lost_hp
	if lost_hp > 0 and mended > 0:
		wall += ", %d mended" % mended
	elif lost_hp <= 0 and mended > 0:
		wall = "Wall: %d health mended" % mended
	var breaches := int(report.get("breaches", 0))
	if breaches > 0:
		wall += " (%s)" % ("a breach" if breaches == 1 else "%d breaches" % breaches)
	_row("wall", "wall", wall)

	var lost: Array = report.get("lost", [])
	for i in mini(lost.size(), MOST_LOST):
		var who: Dictionary = lost[i]
		var epitaph := String(who.get("epitaph", ""))
		_row("lost", "down", "%s is gone. “%s”" % [String(who.get("who", "")), epitaph] if epitaph != "" else "%s is gone." % String(who.get("who", "")), true)
	var hurt: Array = report.get("hurt", [])
	if not hurt.is_empty():
		_row("hurt", "wound", "Hurt in the night: %s" % _join(hurt))

	var ups: Array = report.get("skill_ups", [])
	if not ups.is_empty():
		var bits: Array = []
		for u in ups:
			bits.append("%s %s %d" % [String(u.get("who", "")), String(u.get("skill", "")), int(u.get("value", 0))])
		_row("skills", "focus", "Learned: %s" % ", ".join(bits))

	var events: Array = report.get("events", [])
	for i in mini(events.size(), MOST_EVENTS):
		_row("event", "bell", String(events[i]))

	var mood := String(report.get("mood", ""))
	if mood != "":
		_row("mood", "sun", mood)

	_tip = hud._label("Click or press a key to put this away", Fonts.sans(400), 12, hud.PAPER_INK3)
	_body.add_child(_tip)
	row_kinds.append("tip")
	rows.append(_tip)


## One ruled line: a small picture and the words, with a pencil line above it.
func _row(kind: String, icon_name: String, text: String, quote: bool = false) -> void:
	var rule := ColorRect.new()
	rule.color = hud.PAPER_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(rule)
	var row: HBoxContainer = hud._hbox(8)
	var ic: TextureRect = hud._icon(icon_name, 16, hud.PAPER_INK2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 2)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(ic)
	row.add_child(pad)
	var l: Label = hud._label(text, Fonts.sans(500 if not quote else 400), 14, hud.PAPER_INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120
	row.add_child(l)
	_body.add_child(row)
	rows.append(row)
	row_kinds.append(kind)


func _join(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


# ------------------------------------------------------------------------ layout --

## Where the card goes: at the top, under the crew, between the stores and the clock (the dawn banner
## has gone by the time it comes), as wide as the room allows; it keeps clear of the selection dock
## (to its right, or by dropping the least important rows) when the window is short.
func _layout(shrink: bool = true) -> void:
	if panel == null or not is_inside_tree():
		return
	var origin := get_global_rect().position
	var top := MARGIN
	var bar = hud.get("bar")
	if bar is Control and bar.is_visible_in_tree() and bar.get_global_rect().position.y - origin.y < size.y * 0.5:
		top = bar.get_global_rect().end.y - origin.y + 8.0
	# the room on each side: what the stores and the clock take
	var lo := MARGIN
	var hi := size.x - MARGIN
	var col = hud.get("left_col")
	if col is Control and col.is_visible_in_tree():
		var r: Rect2 = Rect2(col.get_global_rect().position - origin, col.get_global_rect().size)
		if r.size.x > 1.0 and r.end.y > top - 4.0:
			lo = maxf(lo, r.end.x + 8.0)
	var right = hud.get("right_col")
	if right is Control and right.is_visible_in_tree():
		var r: Rect2 = Rect2(right.get_global_rect().position - origin, right.get_global_rect().size)
		if r.size.x > 1.0 and r.end.y > top - 4.0:
			hi = minf(hi, r.position.x - 8.0)
	var width := clampf(minf(MAX_W, hi - lo), 200.0, MAX_W)
	var x := clampf((size.x - width) / 2.0, lo, maxf(lo, hi - width))
	panel.custom_minimum_size.x = width
	panel.size = Vector2(width, 0.0)
	panel.reset_size()
	panel.size = Vector2(width, 0.0)
	# the selection dock, if it is in the way: to its right if there is room, else fewer rows
	var guard := 0
	while guard < 12:
		guard += 1
		var h := panel.get_combined_minimum_size().y
		var dock := _dock_rect(origin)
		if dock.size == Vector2.ZERO or not Rect2(Vector2(x, top), Vector2(width, h)).intersects(dock):
			break
		if dock.end.x + 8.0 + width <= hi and x < dock.end.x + 8.0:
			x = dock.end.x + 8.0
			continue
		# (the rows are only dropped once the words have their widths and the heights can be trusted)
		if not shrink or not _shrink_step():
			break
		panel.reset_size()
	panel.position = Vector2(x, top)
	panel.size = Vector2(width, panel.get_combined_minimum_size().y)


## The selection dock in this card's coordinates, or an empty rectangle when it is not up.
func _dock_rect(origin: Vector2) -> Rect2:
	var dock = hud.get("dock")
	var inspect = hud.get("inspect")
	if dock is Control and inspect is Control and inspect.is_visible_in_tree() and dock.is_visible_in_tree():
		var r: Rect2 = dock.get_global_rect()
		return Rect2(r.position - origin, r.size).grow(6.0)
	return Rect2()


## One step to make the card smaller: first the caption and the tip go, the title is a size smaller
## and the margins and gaps are tighter; then the least important rows. False when there is nothing more to take.
func _shrink_step() -> bool:
	if not _squeezed:
		_squeezed = true
		_caps.visible = false
		_tip.visible = false
		_title.add_theme_font_size_override("font_size", 20)
		# and the page's margins and the gaps between the rows are tighter
		var page: StyleBox = panel.get_theme_stylebox("panel")
		page.content_margin_top = 10.0
		page.content_margin_bottom = 12.0
		_body.add_theme_constant_override("separation", 4)
		return true
	return _drop_one()


## Takes the least important row away (the news, then the skills, then the lost beyond the first,
## then the hurt); false if there is nothing more to drop.
func _drop_one() -> bool:
	for kind in ["event", "skills", "hurt", "lost"]:
		var at := row_kinds.rfind(kind)
		if at < 0 or (kind == "lost" and row_kinds.count("lost") <= 1):
			continue
		var row: Control = rows[at]
		# the ruled line above it goes with it
		var idx := row.get_index()
		if idx > 0:
			var rule := _body.get_child(idx - 1)
			_body.remove_child(rule)
			rule.queue_free()
		_body.remove_child(row)
		row.queue_free()
		rows.remove_at(at)
		row_kinds.remove_at(at)
		_dropped += 1
		return true
	return false


# ---------------------------------------------------------------------- closing --

func _process(dt: float) -> void:
	if not _open:
		return
	if _passes > 0:
		_passes -= 1
		_layout(_passes == 0)
	_t += dt
	if _t >= _seconds:
		_close()
		return
	var left := _seconds - _t
	if left < FADE and not Prefs.on("ui", "reduce_motion"):
		modulate.a = clampf(left / FADE, 0.0, 1.0)


func _on_panel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_close()
		accept_event()


## Any key puts it away (and the game still hears the key); Esc is for this card alone.
func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.keycode == KEY_ESCAPE and is_inside_tree():
		get_viewport().set_input_as_handled()
	_close()


func is_open() -> bool:
	return _open


func close() -> void:
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	set_process(false)
	set_process_input(false)
	hide()
	closed.emit()
	queue_free()
