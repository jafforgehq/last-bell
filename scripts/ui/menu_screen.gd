## The base of the modal menu screens (pause, settings, new game, load, credits, the
## confirm and the first-launch card): a dimmed window with a panel in the middle, a
## heading, a body that scrolls when the window is too short, and a row of buttons at the
## foot. It borrows the HUD's styles through the shell (`hud._style`, `_panel`, `_label`,
## `_button`), so the screens take on the look of the HUD, whatever that is.
##
## A screen does not read the keys itself: the shell hears Esc and calls `on_escape()`,
## and Enter and the arrows work through the controls' own focus. A screen that is
## covered by another is told (`set_active`) so that Tab does not wander into it.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")

## Emitted once, when the screen is closed (the shell then takes it away).
signal closed

## What the shell calls this one ("pause", "settings", ...).
var kind := "screen"
var shell
var hud
var panel: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var foot: HBoxContainer
var title_label: Label
var caption_label: Label
var dim: ColorRect
## The panel is at most this wide (and never wider than the window less a margin).
var max_w := 560.0
## A page of paper with dark ink, not the HUD's dark panel.
var paper := false
## The dimming behind it.
var dim_color := Color(0.03, 0.025, 0.02, 0.62)
## The sound of it closing ("" for none: a screen that closes because a game starts).
var close_sound := "ui_close"
## Over the title the menu there goes out of sight while this is up (the little card does
## not: it leaves the menu showing).
var hides_title := true
var _open := true
var _head: Control
var _wrap: MarginContainer
var _last_focus: Control = null


func setup(shell_node, title: String, caption: String = "") -> void:
	shell = shell_node
	hud = shell.hud
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim = ColorRect.new()
	dim.color = dim_color
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = hud._panel(hud._paper_style() if paper else null)
	center.add_child(panel)
	_wrap = MarginContainer.new()
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		_wrap.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		_wrap.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(_wrap)
	var col: VBoxContainer = hud._vbox(12)
	_wrap.add_child(col)

	var head: VBoxContainer = hud._vbox(2)
	title_label = hud._label(title, Fonts.cond(700), 26, ink())
	head.add_child(title_label)
	caption_label = hud._caps(caption)
	caption_label.add_theme_color_override("font_color", ink3())
	caption_label.visible = caption != ""
	head.add_child(caption_label)
	_head = head
	col.add_child(head)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(scroll)
	body = hud._vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	foot = hud._hbox(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(foot)

	_build_body()
	_build_foot()
	resized.connect(_layout)
	# a line that appears (an error under a field) makes the body taller: the scroll's room follows
	body.minimum_size_changed.connect(func(): _layout.call_deferred())
	_layout()
	# wrapped text only knows its height once it has a width: lay out again a frame on
	_layout.call_deferred()


# ------------------------------------------------- what a screen fills in --

## Fills `body` (called once, from setup).
func _build_body() -> void:
	pass


## Fills `foot` (called once, from setup).
func _build_foot() -> void:
	pass


## The control that has the keyboard when the screen opens (the first button if not set).
func default_focus() -> Control:
	return _first_focusable(self)


## Esc: the screen closes (a screen with something to ask first does that instead).
func on_escape() -> void:
	close()


# ------------------------------------------------------------- colours --

## The ink of the text (dark on paper, cream on the HUD's panel).
func ink() -> Color:
	return hud.PAPER_INK if paper else hud.INK


func ink2() -> Color:
	return hud.PAPER_INK2 if paper else hud.INK2


func ink3() -> Color:
	return hud.PAPER_INK3 if paper else hud.INK3


# --------------------------------------------------------------- pieces --

## A few lines of words that wrap.
func note(text: String, color: Color = Color.TRANSPARENT, size: int = 14) -> Label:
	var l: Label = hud._label(text, Fonts.sans(400), size, color if color.a > 0.0 else ink2())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 200
	return l


## A small heading over a group of rows.
func section(text: String) -> Label:
	var l: Label = hud._caps(text)
	l.add_theme_color_override("font_color", ink3())
	return l


func line() -> Control:
	var r := ColorRect.new()
	r.color = hud.PAPER_LINE if paper else hud.LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A button of the shell's kind (focusable, with the click sound; for paper if this is a page).
func button(text: String, primary: bool = false) -> Button:
	return shell.button(text, primary, paper)


# ---------------------------------------------------------------- layout --

func _layout() -> void:
	if panel == null or not is_inside_tree():
		return
	var pw := minf(size.x - 32.0, max_w)
	panel.custom_minimum_size.x = maxf(pw, 0.0)
	# the body scrolls when the window is too short for everything
	var frame: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	var chrome: float = _head.get_combined_minimum_size().y + foot.get_combined_minimum_size().y + 24.0 + frame.y + 12.0
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(96.0, size.y - 32.0 - chrome))


# ---------------------------------------------------------------- focus --

func focus_default() -> void:
	if not is_inside_tree():
		return
	var c := _last_focus if _last_focus != null and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree() else default_focus()
	if c != null and c.focus_mode != Control.FOCUS_NONE:
		c.grab_focus()


## The first control under `n` that could have the keyboard.
func _first_focusable(n: Node) -> Control:
	if n is Control and n.focus_mode == Control.FOCUS_ALL and n.is_visible_in_tree():
		if not (n is BaseButton and n.disabled):
			return n
	for c in n.get_children():
		var f := _first_focusable(c)
		if f != null:
			return f
	return null


func remember_focus() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_last_focus = f if f != null and is_ancestor_of(f) else null


## Another screen is on top of this one (false) or has gone (true).
func set_active(on: bool) -> void:
	Kit.set_focusable(self, on)


func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	_open = false
	closed.emit()
