## One call of the radio that waits for an answer (round 17, slice 1; scripts/sim/radio.gd `raise_call`), as a small block: what kind of
## news it is, the title, the line under it, a countdown bar, the seconds left and what is taken when they run out, and a button for
## each way to answer. When the call has been settled (answered, or its default taken) the buttons and the countdown give way to what
## came of it. The News panel stacks one for each open call; the call card is one of them on its own board.
##
## `setup(host, radio_getter, options)`: `host` is the HUD (it lends its looks, see radio_kit.gd); `radio_getter` a Callable that
## returns the radio (or null); `options` (all optional): "speed_getter" (a Callable returning the pace of the player's clock against the game's normal one: 1 to 3 in the yard, a
## third in a place, so that the seconds are the player's: at 3x a call has a third of the seconds); "slim" (round 18: the strip the radio
## panel keeps under its tabs while another page is up: the title, the countdown and the options side by side in a row that wraps, without the
## kind or the line under the title). `show_entry(entry)` points the view at an entry of the radio's
## log; `refresh()` brings it up to date (the countdown, the result). Answering calls `radio.answer(id, option_id)`; it never pauses
## anything.
extends VBoxContainer

const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The height of an option's button, and of a slim one (the most `level` there is).
const BUTTON_H := 28.0
const BUTTON_H_SLIM := 24.0
const MAX_LEVEL := 3

## Emitted when a button was pressed and the radio took the answer.
signal answered(call_id: int, option_id: String)

var host
var options := {}
var entry_id := 0
var kind_label: Label
var title_label: Label
var sub_label: Label
## The voice's opinion under the line (round 20, "Ana, the medic: treat them."): the initiative module's, told only at level 0.
var opinion_label: Label
var bar
var count_label: Label
var result_label: Label
## Option id to its button, in the order of the call's options.
var buttons := {}
## How much of the call is told: 0 all of it; 1 without the line under the title; 2 and without the kind (the colour bar of the card says it);
## 3 and with slimmer buttons. A card that has little room asks for more (`set_level`, `CallCard.fit`).
var level := 0
## The slim form (see `setup`): the options are in a row that wraps, not one under the other.
var slim := false
var _radio_getter: Callable
var _buttons_box: Container
var _built := false


func setup(host_hud, radio_getter: Callable, opts: Dictionary = {}) -> void:
	host = host_hud
	_radio_getter = radio_getter
	options = opts
	if _built:
		return
	_built = true
	slim = bool(opts.get("slim", false))
	if slim:
		level = 2
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind_label = host._caps("", host.INK2)
	add_child(kind_label)
	title_label = host._label("", Fonts.sans(600), 14, host.INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 100
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title_label)
	sub_label = host._label("", Fonts.sans(400), 12, host.INK2)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.custom_minimum_size.x = 100
	sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(sub_label)
	opinion_label = host._label("", Fonts.sans(600), 12, host.ACCENT)
	opinion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	opinion_label.custom_minimum_size.x = 100
	opinion_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opinion_label.visible = false
	add_child(opinion_label)
	bar = host.Bar.new()
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.groove = host.frame("bar_track")
	add_child(bar)
	count_label = host._label("", Fonts.sans(400), 12, host.INK2)
	count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_label.custom_minimum_size.x = 100
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(count_label)
	result_label = host._label("", Fonts.sans(600), 13, host.OK)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size.x = 100
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.visible = false
	add_child(result_label)
	if slim:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buttons_box = flow
	else:
		_buttons_box = host._vbox(4)
	add_child(_buttons_box)


## Points the view at an entry (a call, open or settled) and brings it up to date. The buttons are made once for each call.
func show_entry(e: Dictionary) -> void:
	if int(e.id) != entry_id:
		entry_id = int(e.id)
		_rebuild(e)
	refresh()


## Tells less of the call (see `level`), for a card that has little room.
func set_level(l: int) -> void:
	level = clampi(l, 0, MAX_LEVEL)
	_apply_level()


func _apply_level() -> void:
	if kind_label == null:
		return
	kind_label.visible = level < 2
	sub_label.visible = level < 1 and sub_label.text != ""
	opinion_label.visible = level < 1 and opinion_label.text != ""
	for b in buttons.values():
		b.custom_minimum_size.y = BUTTON_H if level < 3 else BUTTON_H_SLIM


func _rebuild(e: Dictionary) -> void:
	for c in _buttons_box.get_children():
		_buttons_box.remove_child(c)
		c.queue_free()
	buttons.clear()
	kind_label.text = RadioKit.kind_name(String(e.kind)).to_upper()
	kind_label.add_theme_color_override("font_color", RadioKit.kind_color(host, String(e.kind)))
	title_label.text = String(e.text)
	sub_label.text = String(e.sub)
	sub_label.visible = String(e.sub) != ""
	opinion_label.text = ""
	opinion_label.visible = false
	for o in e.options:
		var b: Button = RadioKit.small_button(host, String(o.label), BUTTON_H if level < 3 else BUTTON_H_SLIM, 13)
		b.size_flags_horizontal = Control.SIZE_FILL if slim else Control.SIZE_EXPAND_FILL
		# an idea's yes carries its price ("Yes: put up a workshop (30 scrap)"): a long word of it wraps rather than widening the card. Not in
		# the slim strip: its buttons sit in a row that wraps as whole buttons, and a button that wraps its own words there shrinks to its
		# longest word and grows tall (the strip was 364 px high, with three options, and pushed the radio panel over the clock)
		if not slim:
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_pressed.bind(String(o.id)))
		_buttons_box.add_child(b)
		buttons[String(o.id)] = b
	_apply_level()


func _speed() -> float:
	var g = options.get("speed_getter")
	if g is Callable and g.is_valid():
		var v := float(g.call())
		return v if v > 0.0 else 1.0
	return 1.0


## The seconds the call has left (0 once it is settled or the entry is gone).
func seconds_left() -> float:
	var radio = _radio_getter.call()
	var e := RadioKit.entry_of(radio, entry_id)
	if e.is_empty() or String(e.answered) != "":
		return 0.0
	return RadioKit.left_seconds(radio, e, _speed())


## Brings the view in line with its entry: the seconds and the bar while it waits, what came of it once it is settled.
func refresh() -> void:
	var radio = _radio_getter.call()
	var e := RadioKit.entry_of(radio, entry_id)
	if e.is_empty():
		return
	var open: bool = not e.options.is_empty() and String(e.answered) == ""
	_show_opinion(radio, e, open)
	_buttons_box.visible = open
	bar.visible = open
	count_label.visible = open
	result_label.visible = not open
	if open:
		var left := RadioKit.left_seconds(radio, e, _speed())
		var total := RadioKit.total_seconds(radio, e, _speed())
		var f := clampf(left / total, 0.0, 1.0)
		if not is_equal_approx(bar.value, f):
			bar.value = f
			bar.queue_redraw()
		var c: Color = host.DANGER if f < 0.25 else host.ACCENT
		if bar.color != c:
			bar.color = c
			bar.queue_redraw()
		var fallback := RadioKit.option_label(e, String(e.default))
		var words := "%d s" % ceili(left)
		if fallback != "":
			words += ": %s by default" % fallback
		if count_label.text != words:
			count_label.text = words
		return
	var picked := RadioKit.option_label(e, String(e.answered))
	var said := String(e.result)
	if said == "":
		said = picked if picked != "" else "Done"
	if bool(e.by_default):
		said += " (by default)"
	if result_label.text != said:
		result_label.text = said


## The voice's opinion of the call while it waits (it is live: a wall that worsens changes it); none once it is settled. It is a line
## and nothing more: no option is lit and the call's own default is not touched.
func _show_opinion(radio, e: Dictionary, open: bool) -> void:
	var words := RadioKit.opinion_text(radio, e) if open else ""
	if opinion_label.text != words:
		opinion_label.text = words
	opinion_label.visible = level < 1 and words != ""


func _on_pressed(option_id: String) -> void:
	var radio = _radio_getter.call()
	if radio == null:
		return
	if radio.answer(entry_id, option_id):
		answered.emit(entry_id, option_id)
		refresh()
