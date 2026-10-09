## The loot window (INV-UI): the container she is searching, as its own small grid beside the backpack. The sim reveals its stacks one by one (`sim.inv.loot_open.revealed`): the stacks not
## found yet are dark "?" cells that turn into the item when found (a short glow, none under Reduce motion). Take all (Space or Enter, and the button) moves everything found that fits;
## a drag or a double-click takes one stack. It never takes a key itself and never pauses the game: `inv_ui.gd` owns the keys, the drag and the closing (Esc, Tab, walking more than three
## tiles away).
extends PanelContainer

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvGridScript := preload("res://scripts/ui/inv_grid.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")

var ctl
var hud
var grid_ctl
var title: Label
var status: Label
var take_button: Button
var close_button: Button
var hint: Label
## The container shown (its id), how many stacks were found when last read.
var shown_id := ""
var found := 0
var _status_text := ""


func setup(controller, hud_node, cell: float) -> void:
	ctl = controller
	hud = hud_node
	name = "InvLootWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 9
		st.content_margin_bottom = 10
	add_theme_stylebox_override("panel", st)
	var col: VBoxContainer = hud._vbox(6)
	add_child(col)
	var head: HBoxContainer = hud._hbox(8)
	title = hud._label("CONTAINER", Fonts.cond(700, 1), 15, hud.ACCENT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 60
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_button = RadioKit.small_button(hud, "×", 26.0, 18)
	close_button.custom_minimum_size.x = 30.0
	close_button.pressed.connect(func(): ctl.close_loot())
	head.add_child(close_button)
	col.add_child(head)
	status = hud._label("", Fonts.sans(500, 0), 13, hud.INK2)
	col.add_child(status)
	grid_ctl = InvGridScript.new()
	grid_ctl.name = "InvLootGrid"
	grid_ctl.setup(ctl, "loot", {"w": 4, "h": 3, "cells": []}, cell)
	col.add_child(grid_ctl)
	var row: HBoxContainer = hud._hbox(8)
	take_button = RadioKit.small_button(hud, "Take all", 28.0, 14)
	take_button.pressed.connect(func(): ctl.take_all_pressed())
	row.add_child(take_button)
	hint = hud._label("", Fonts.sans(400), 13, hud.INK3)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 80
	row.add_child(hint)
	col.add_child(row)
	set_texts()


func set_texts() -> void:
	close_button.tooltip_text = "Close the container\nKey: Esc, or %s" % ControlsTable.key_text("inv")
	take_button.tooltip_text = "Take everything that fits in the pack\nKey: %s" % ControlsTable.key_text("inv_take")
	hint.text = "Drag, or double-click, to take. It closes when you walk away."


func set_cell(cell: float) -> void:
	grid_ctl.set_cell(cell)


## Shows the container `lo` ({"id", "name", "grid", "revealed"}); returns the stacks found since the last look (they glow).
func show_container(lo: Dictionary) -> void:
	var g: Dictionary = lo.grid
	var id := String(lo.id)
	var rev := int(lo.revealed)
	var n: int = g.cells.size()
	if id != shown_id:
		shown_id = id
		found = rev
		grid_ctl.flash.clear()
	elif rev > found:
		for i in range(found, rev):
			grid_ctl.glow(i)
		found = rev
	else:
		found = rev
	if grid_ctl.grid != g:
		grid_ctl.set_grid(g)
	grid_ctl.revealed = rev if rev < n else -1
	grid_ctl.queue_redraw()
	var nm := String(lo.get("name", ""))
	title.text = nm.to_upper() if nm != "" else "CONTAINER"
	title.tooltip_text = nm
	var words := ""
	if n == 0:
		words = "Empty"
	elif rev < n:
		words = "Searching... %d of %d found" % [rev, n]
	else:
		words = "%d found" % n if n > 1 else "1 found"
	if words != _status_text:
		_status_text = words
		status.text = words
	take_button.disabled = rev <= 0
