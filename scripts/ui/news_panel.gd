## The News panel (round 17, slice 1): a compact, non-modal log of what the radio heard, fed from a radio's `news`. At the top the
## calls that still wait for an answer, each with its options and a countdown (call_view.gd), and under them the log, newest first:
## a mark of the kind's colour, the kind in small capitals, the hour, the words, the line under them and, for a call that was settled,
## what came of it ("Holding (by default)"). A dot marks a line the player has not seen yet. It never pauses the game and takes no key.
##
## `setup(host, radio_getter, options)` as call_view.gd (the HUD lends its looks; the radio comes from the Callable; the options are
## handed on to the views). `refresh()` brings it up to date (the HUD does it with each update while it is open). The panel is as wide
## as its `custom_minimum_size.x` (the HUD gives it the clock's width) and as tall as `fit(max_h)` lets it be; what does not fit scrolls.
##
## Round 18: it is also the News PAGE of the radio panel (radio_panel.gd), which has the page contract (`setup(host, sim_getter, options)`,
## `refresh()`, `focus_on(id)`, `full_page()`): the Callable may return the radio or a sim that has one, and with the option "embedded"
## the panel wears no board of its own (the radio panel's is behind it) and has no title (the tab says it).
## Lines are UNREAD while their id is above `seen_id`; `mark_read()` sets it to the newest (the HUD does when the panel is shut). The
## radio keeps the number (`news_seen`), so the yard's panel and a place's share it: what is read in one is read in the other. A
## radio without that field (a test's stand-in) leaves it to the panel.
extends PanelContainer

const CallView := preload("res://scripts/ui/call_view.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## Emitted when a call was answered through the panel.
signal answered(call_id: int, option_id: String)

## How many lines of the log are drawn (the radio keeps 60).
const MAX_ROWS := 60
## The least the list is tall.
const MIN_LIST_H := 40.0

var host
var options := {}
## The newest line the player has seen: everything above it is unread. It is the radio's own number when it has one.
var seen_id: int:
	get:
		var radio = _radio()
		if radio != null and radio.get("news_seen") != null:
			return int(radio.news_seen)
		return _own_seen
	set(value):
		var radio = _radio()
		if radio != null and radio.get("news_seen") != null:
			radio.news_seen = value
		else:
			_own_seen = value
var _own_seen := 0
## One view for each open call, oldest first (call_view.gd).
var call_views: Array = []
## The lines of the log, newest first: {"id", "kind", "unread", "color", "box"}.
var rows: Array = []
var scroll: ScrollContainer
var body: VBoxContainer
var title_label: Label
var count_label: Label
var embedded := false
var head: HBoxContainer
var _radio_getter: Callable
var _calls_box: VBoxContainer
var _log_box: VBoxContainer
var _empty_label: Label
var _compact := false
var _sig := ""
var _built := false


func setup(host_hud, radio_getter: Callable, opts: Dictionary = {}) -> void:
	host = host_hud
	_radio_getter = func(): return _as_radio(radio_getter.call() if radio_getter.is_valid() else null)
	options = opts
	if _built:
		return
	_built = true
	embedded = bool(opts.get("embedded", false))
	if embedded:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		add_theme_stylebox_override("panel", host._style(host.PANEL, 6, host.LINE, true, "panel"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = host._vbox(6)
	add_child(col)
	head = host._hbox(6)
	title_label = host._caps("News")
	title_label.visible = not embedded
	head.add_child(title_label)
	head.add_child(host._spacer())
	count_label = host._label("", Fonts.cond(700, 0), 12, host.ACCENT)
	head.add_child(count_label)
	col.add_child(head)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	col.add_child(scroll)
	body = host._vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_calls_box = host._vbox(8)
	body.add_child(_calls_box)
	_log_box = host._vbox(0)
	body.add_child(_log_box)
	_empty_label = host._label("Nothing on the radio yet", Fonts.sans(400), 13, host.INK3)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.custom_minimum_size.x = 100
	body.add_child(_empty_label)
	visible = false


func _radio():
	return _radio_getter.call() if _radio_getter.is_valid() else null


## The radio of what the Callable gave: the radio itself (anything that has a log of news: a place's, a test's stand-in) or a sim that has one.
static func _as_radio(r):
	if r == null:
		return null
	if r.get("news") != null:
		return r
	var inner = r.get("radio")
	return inner if inner != null else r


## The page contract (radio_panel.gd): the news has nothing to focus on and no fuller page.
func focus_on(_id: String) -> void:
	scroll.scroll_vertical = 0


func full_page() -> void:
	pass


## The narrow form (a small window): the hours are left off the lines and the panel is as wide as the clock is then.
func set_compact(on: bool) -> void:
	if on != _compact:
		_compact = on
		_sig = ""


func is_compact() -> bool:
	return _compact


# ----------------------------------------------------------------------- reading --

## The ids of the lines the player has not seen (newest first), calls included.
func unread_ids() -> Array:
	var out: Array = []
	var radio = _radio()
	if radio == null:
		return out
	for i in range(radio.news.size() - 1, -1, -1):
		if int(radio.news[i].id) > seen_id:
			out.append(int(radio.news[i].id))
	return out


func unread() -> int:
	return unread_ids().size()


## Everything is seen now.
func mark_read() -> void:
	var radio = _radio()
	if radio != null:
		seen_id = int(radio.latest_id())
		_sig = ""
		refresh()


## The ids of the lines of the log, newest first (the open calls are above them, not among them).
func row_ids() -> Array:
	var out: Array = []
	for r in rows:
		out.append(int(r.id))
	return out


func row_kinds() -> Array:
	var out: Array = []
	for r in rows:
		out.append(String(r.kind))
	return out


func row_colors() -> Array:
	var out: Array = []
	for r in rows:
		out.append(r.color)
	return out


## The ids of the open calls at the top, oldest first.
func call_ids() -> Array:
	var out: Array = []
	for v in call_views:
		out.append(int(v.entry_id))
	return out


# ------------------------------------------------------------------------ building --

## Brings the panel up to date: the calls (their countdowns every time), the log (when something in it changed).
func refresh() -> void:
	var radio = _radio()
	if radio == null:
		return
	var open: Array = RadioKit.by_urgency(radio.open_calls())    # (the card's own call first, then the others: round 19)
	var open_ids: Array = []
	for e in open:
		open_ids.append(int(e.id))
	_sync_calls(open, open_ids)
	for v in call_views:
		v.refresh()
	var sig := "%s|%d|%d|%s" % [str(_compact), seen_id, radio.news.size(), str(open_ids)]
	for e in radio.news:
		sig += "|%d:%s" % [int(e.id), String(e.answered)]
	if sig != _sig:
		_sig = sig
		_rebuild_log(radio, open_ids)
	var n := unread()
	var words := "%d new" % n if n > 0 else ""
	if count_label.text != words:
		count_label.text = words
	if embedded and head.visible != (words != ""):
		head.visible = words != ""


func _sync_calls(open: Array, open_ids: Array) -> void:
	var have: Array = []
	for v in call_views:
		have.append(int(v.entry_id))
	if have == open_ids:
		return
	for v in call_views:
		_calls_box.remove_child(v)
		v.queue_free()
	call_views.clear()
	# a new call is a decision: it is brought into view
	scroll.scroll_vertical = 0
	for e in open:
		var v = CallView.new()
		_calls_box.add_child(v)
		v.setup(host, _radio_getter, options)
		v.answered.connect(_on_call_answered)
		v.show_entry(e)
		call_views.append(v)
		# a call stands apart from the log: a rule under it
		var rule := ColorRect.new()
		rule.color = host.LINE2
		rule.custom_minimum_size = Vector2(0, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_calls_box.add_child(rule)


func _on_call_answered(id: int, option_id: String) -> void:
	answered.emit(id, option_id)
	refresh()


func _rebuild_log(radio, open_ids: Array) -> void:
	for c in _log_box.get_children():
		_log_box.remove_child(c)
		c.queue_free()
	rows.clear()
	var shown := 0
	for i in range(radio.news.size() - 1, -1, -1):
		var e: Dictionary = radio.news[i]
		if open_ids.has(int(e.id)) or shown >= MAX_ROWS:
			continue
		shown += 1
		var unread_now: bool = int(e.id) > seen_id
		var box := _row(e, unread_now)
		_log_box.add_child(box)
		rows.append({"id": int(e.id), "kind": String(e.kind), "unread": unread_now, "color": RadioKit.kind_color(host, String(e.kind)), "box": box})
	_empty_label.visible = rows.is_empty() and call_views.is_empty()


## One line of the log.
func _row(e: Dictionary, unread_now: bool) -> Control:
	var kind_c: Color = RadioKit.kind_color(host, String(e.kind))
	var outer: VBoxContainer = host._vbox(0)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rule := ColorRect.new()
	rule.color = host.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(rule)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(pad)
	var row: HBoxContainer = host._hbox(6)
	pad.add_child(row)
	# the mark of what has not been seen: a gold dot; a seen line has a blank of the same width
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_meta("unread", unread_now)
	if unread_now:
		dot.draw.connect(func(): dot.draw_circle(Vector2(4, 6), 3.5, host.ACCENT))
	row.add_child(dot)
	var col: VBoxContainer = host._vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head: HBoxContainer = host._hbox(6)
	head.add_child(host._label(RadioKit.kind_name(String(e.kind)).to_upper(), Fonts.cond(700, 1), 12, kind_c))
	head.add_child(host._spacer())
	var when := RadioKit.clock_text(float(e.hour)) if _compact else "Day %d, %s" % [int(e.day), RadioKit.clock_text(float(e.hour))]
	head.add_child(host._label(when, Fonts.sans(400), 12, host.INK3))
	col.add_child(head)
	var text: Label = host._label(String(e.text), Fonts.sans(600), 13, host.INK if unread_now else host.INK2)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 80
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(text)
	if String(e.sub) != "":
		var sub: Label = host._label(String(e.sub), Fonts.sans(400), 12, host.INK2)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = 80
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(sub)
	if String(e.answered) != "":
		var said := String(e.result)
		if said == "":
			var picked := RadioKit.option_label(e, String(e.answered))
			said = "Answered: %s" % picked if picked != "" else ""
		if said != "" and bool(e.by_default):
			said += " (by default)"
		if said != "":
			var res: Label = host._label(said, Fonts.sans(600), 12, host.OK)
			res.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			res.custom_minimum_size.x = 80
			res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(res)
	return outer


# ------------------------------------------------------------------------- fitting --

## Makes the panel as tall as its lines need, at most `max_h` (what does not fit scrolls).
func fit(max_h: float) -> void:
	var chrome := get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	var want := body.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = clampf(want, MIN_LIST_H, maxf(MIN_LIST_H, max_h - chrome))
