## The call card (round 17, slice 1): a small board under the HUD's alerts for the OLDEST call of the radio that waits for an answer,
## so a decision is never hidden behind the News panel being shut: the kind, the title, the line under it, a countdown bar, the
## options as buttons. It never pauses the game and never takes a key. When the call is settled (answered, or its default taken by
## the rules) the card shows what came of it for `result_ms`, then goes, or gives way at once to the next open call.
##
## `setup(host, radio_getter, options)` as call_view.gd (the HUD lends its looks; the radio comes from the Callable; the options are
## handed on to the view). `refresh()` is called whenever the HUD is updated; the card is only visible while it has something to show.
extends PanelContainer

const CallView := preload("res://scripts/ui/call_view.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")

## Emitted when a button was pressed and the radio took the answer.
signal answered(call_id: int, option_id: String)

## How long (real milliseconds) the result of a settled call stays up.
const RESULT_MS := 3000

var host
var view
## How long the result stays: a test shortens it.
var result_ms := RESULT_MS
## The id of the call the card shows (0: none).
var shown_id := 0
## True while the News panel is up and there is no room for both: the panel shows the open calls itself, so the card steps aside
## (the HUD sets it; `shown_id` and the result still follow the radio).
var suppressed := false
var _radio_getter: Callable
var _result_until := 0
var _showing_result := false
var _bar_color := Color.WHITE


func setup(host_hud, radio_getter: Callable, opts: Dictionary = {}) -> void:
	host = host_hud
	_radio_getter = radio_getter
	if view != null:
		view.setup(host, radio_getter, opts)
		return
	var st: StyleBox = host._style(host.PANEL, 6, host.LINE2, true, "panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 16
	else:
		st.content_margin_left = maxf(st.content_margin_left, 16.0)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	view = CallView.new()
	add_child(view)
	view.setup(host, radio_getter, opts)
	view.answered.connect(_on_answered)
	draw.connect(_draw_edge)
	visible = false


## A bar of the kind's colour down the left edge (as the alert slips have).
func _draw_edge() -> void:
	draw_rect(Rect2(5, 6, 3, maxf(0.0, size.y - 12.0)), _bar_color)


func _on_answered(id: int, option_id: String) -> void:
	answered.emit(id, option_id)
	refresh()


## The card steps aside (or comes back): see `suppressed`.
func set_suppressed(on: bool) -> void:
	suppressed = on
	visible = shown_id != 0 and not on


## Whether the card is showing what came of a call rather than the call.
func is_showing_result() -> bool:
	return visible and _showing_result


## Takes the card down at once (the HUD does when there is no avatar).
func clear() -> void:
	shown_id = 0
	_showing_result = false
	_result_until = 0
	visible = false


## The oldest open call; else, for a moment, what came of the one that was just settled; else nothing.
func refresh() -> void:
	var radio = _radio_getter.call() if _radio_getter.is_valid() else null
	if radio == null:
		clear()
		return
	var calls: Array = radio.open_calls()
	if not calls.is_empty():
		var e: Dictionary = calls[0]
		_showing_result = false
		_result_until = 0
		shown_id = int(e.id)
		_show(e)
		return
	if shown_id != 0:
		var e := RadioKit.entry_of(radio, shown_id)
		if not e.is_empty() and String(e.answered) != "":
			var now := Time.get_ticks_msec()
			if _result_until == 0:
				_result_until = now + result_ms
			if now < _result_until:
				_showing_result = true
				_show(e)
				return
	clear()


func _show(e: Dictionary) -> void:
	view.show_entry(e)
	var c: Color = RadioKit.kind_color(host, String(e.kind))
	if c != _bar_color:
		_bar_color = c
		queue_redraw()
	visible = not suppressed
