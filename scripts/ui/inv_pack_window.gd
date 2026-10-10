## The backpack window (INV2): her pack as a grid at the left (8 by 4 cells of 32 to 36 points by default), and at the right Ruth with her kit (scripts/ui/inv_doll.gd: the shotgun and the
## swing in their slots, four quick slots on her belt), in the HUD's own slim board (the dark green panel with a thin trim). One line above the grid says what it is and how full it is; the how-tos
## are the tooltips' and the Controls page's. Built once by `inv_ui.gd` and only brought up to date when the sim's pack changed (`refresh`). It never takes a key and never pauses the game.
extends PanelContainer

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")
const InvGeom := preload("res://scripts/ui/inv_geom.gd")
const InvGridScript := preload("res://scripts/ui/inv_grid.gd")
const InvDoll := preload("res://scripts/ui/inv_doll.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")

var ctl
var hud
var grid_ctl
var title: Label
var fill_label: Label
var close_button: Button
var doll
var _fill_text := ""


func setup(controller, hud_node, cell: float) -> void:
	ctl = controller
	hud = hud_node
	name = "InvPackWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _style())
	var row: HBoxContainer = hud._hbox(8)
	add_child(row)
	var left: VBoxContainer = hud._vbox(3)
	row.add_child(left)
	var head: HBoxContainer = hud._hbox(6)
	head.add_child(PackBadge.new())
	title = hud._label("BACKPACK", Fonts.cond(700, 1), 14, hud.ACCENT)
	head.add_child(title)
	fill_label = hud._label("", Fonts.cond(700, 0), 14, hud.INK2)
	head.add_child(fill_label)
	left.add_child(head)
	grid_ctl = InvGridScript.new()
	grid_ctl.name = "InvPackGrid"
	grid_ctl.setup(ctl, "pack", {"w": 8, "h": 4, "cells": []}, cell)
	left.add_child(grid_ctl)
	doll = InvDoll.new()
	doll.setup(ctl)
	row.add_child(doll)
	close_button = RadioKit.small_button(hud, "×", 22.0, 16)
	close_button.custom_minimum_size = Vector2(24.0, 22.0)
	close_button.size = Vector2(24.0, 22.0)
	close_button.position = Vector2(InvDoll.W - 24.0, 0.0)
	close_button.pressed.connect(func(): ctl.close_pack())
	doll.add_child(close_button)
	set_texts()


func _style() -> StyleBox:
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel_slim")
	if st is StyleBoxFlat:
		st.content_margin_left = 8
		st.content_margin_right = 8
		st.content_margin_top = 7
		st.content_margin_bottom = 8
	else:
		st.content_margin_left = 9
		st.content_margin_right = 9
		st.content_margin_top = 8
		st.content_margin_bottom = 10
	return st


## The words that name keys: read from the controls table so that they cannot disagree with it.
func set_texts() -> void:
	close_button.tooltip_text = "Close the backpack\nKey: %s, or Esc" % ControlsTable.key_text("inv")
	tooltip_text = ""


func set_cell(cell: float) -> void:
	grid_ctl.set_cell(cell)


## Each time the sim's pack changed (or the gun did): the grid, the fullness and the kit.
func refresh(sim, pack: Dictionary, grid_changed: bool = true) -> void:
	if grid_changed:
		if not is_same(grid_ctl.grid, pack):
			grid_ctl.set_grid(pack)
		grid_ctl.queue_redraw()
		var f := InvGeom.fullness(pack, Callable(InvApi, "size_of")) if not pack.is_empty() else Vector2i.ZERO
		var t := "%d / %d" % [f.x, f.y]
		if t != _fill_text:
			_fill_text = t
			fill_label.text = t
			fill_label.tooltip_text = "Cells used of the backpack"
	doll.refresh(sim, pack)


## The small pack drawn at the head of the window.
class PackBadge:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var ic := load("res://scripts/ui/inv_icons.gd")
		ic.draw_pack(self, Rect2(Vector2.ZERO, size))
