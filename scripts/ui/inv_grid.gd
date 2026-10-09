## One grid of the inventory windows (INV-UI): the backpack's, a container's. A Control that DRAWS its cells and stacks once and again only when told (`queue_redraw`: the windows do it when
## the sim's grid changed, the pointer moved onto another stack, or a reveal is fading): no node for a cell or a stack, so a full pack is one draw call set and no layout.
##
## The grid is the sim's own dictionary ({"w", "h", "cells": [{"item", "x", "y", "rot", "count"}]}); the controller (scripts/ui/inv_ui.gd, `ctl`) is given every mouse event and every
## tooltip question, and owns the drag: this control only knows how to draw (the dragged stack dimmed, the pointer's stack outlined, the stacks not yet found as a "?") and where a point is.
extends Control

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")
const InvGeom := preload("res://scripts/ui/inv_geom.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")

const PAD := 2.0
const BG := Color(0.035, 0.07, 0.06, 0.92)
const BG_ALT := Color(0.06, 0.10, 0.085, 0.92)
const LINE := Color(0.93, 0.96, 0.89, 0.16)
const EDGE := Color("#d2a94e")
const ACCENT := Color("#f0c24a")
const INK := Color("#eeeadd")
const INK3 := Color("#a8ae9d")
## How long (seconds) a stack that was just found glows.
const FLASH_S := 0.45

## "pack" or "loot": which grid of the controller this is.
var kind := "pack"
var ctl
var grid: Dictionary = {}
var cell := 48.0
## How many of the first stacks are shown (-1: all of them); the others are "?".
var revealed := -1
## The stack the pointer is over (-1: none), and the one that is being dragged (-1: none).
var hover_index := -1
var held_index := -1
## Stacks that were just found: index -> seconds left of the glow.
var flash := {}
## How many times the grid has been drawn (the cost probe and the tests read it: a grid is drawn when something changed, not each frame).
var draws := 0

var _size_fn := Callable()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_size_fn = Callable(InvApi, "size_of")


## Points the control at a grid and a cell size (its minimum size follows).
func setup(controller, grid_kind: String, g: Dictionary, cell_px: float) -> void:
	ctl = controller
	kind = grid_kind
	grid = g
	cell = cell_px
	custom_minimum_size = natural_size()
	queue_redraw()


func set_cell(cell_px: float) -> void:
	if is_equal_approx(cell, cell_px):
		return
	cell = cell_px
	custom_minimum_size = natural_size()
	queue_redraw()


func set_grid(g: Dictionary) -> void:
	grid = g
	custom_minimum_size = natural_size()
	queue_redraw()


func natural_size() -> Vector2:
	return Vector2(float(int(grid.get("w", 0))) * cell + PAD * 2.0, float(int(grid.get("h", 0))) * cell + PAD * 2.0)


func cols() -> int:
	return int(grid.get("w", 0))


func rows() -> int:
	return int(grid.get("h", 0))


## The cell under a point in this control's pixels ((-1, -1) outside the cells).
func cell_at(local: Vector2) -> Vector2i:
	return InvGeom.cell_at(local, cell, cols(), rows(), PAD)


func cell_at_global(p: Vector2) -> Vector2i:
	return cell_at(p - get_global_rect().position)


## The stack under a point in this control's pixels (-1 for none, and for one that is not found yet when `only_shown`).
func index_at(local: Vector2, only_shown: bool = false) -> int:
	var c := cell_at(local)
	if c.x < 0:
		return -1
	var i := InvGeom.index_at(grid, _size_fn, c)
	if i >= 0 and only_shown and revealed >= 0 and i >= revealed:
		return -1
	return i


## The pixels of a stack's footprint in this control.
func rect_of(index: int) -> Rect2:
	return InvGeom.stack_rect(grid.cells[index], _size_fn, cell, PAD)


func set_hover(i: int) -> void:
	if i != hover_index:
		hover_index = i
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if i >= 0 else Control.CURSOR_ARROW
		queue_redraw()


func set_held(i: int) -> void:
	if i != held_index:
		held_index = i
		queue_redraw()


## A stack was just found: it glows for a moment (nothing under Reduce motion or Reduce flashes).
func glow(i: int) -> void:
	if Access.calm_flashes():
		return
	flash[i] = FLASH_S
	set_process(true)
	queue_redraw()


func _process(dt: float) -> void:
	if flash.is_empty():
		set_process(false)
		return
	for i in flash.keys():
		flash[i] = float(flash[i]) - dt
		if float(flash[i]) <= 0.0:
			flash.erase(i)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ctl != null:
		ctl.grid_input(self, ev)


func _get_tooltip(at_position: Vector2) -> String:
	return ctl.tip_text(self, at_position) if ctl != null else ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and ctl != null:
		ctl.grid_exit(self)


# ------------------------------------------------------------------------------- drawing --

func _draw() -> void:
	draws += 1
	if grid.is_empty():
		return
	var cs := cols()
	var rs := rows()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for y in rs:
		for x in cs:
			if (x + y) % 2 == 1:
				draw_rect(Rect2(Vector2(PAD + float(x) * cell, PAD + float(y) * cell), Vector2(cell, cell)), BG_ALT)
	for x in cs + 1:
		draw_line(Vector2(PAD + float(x) * cell, PAD), Vector2(PAD + float(x) * cell, PAD + float(rs) * cell), LINE, 1.0)
	for y in rs + 1:
		draw_line(Vector2(PAD, PAD + float(y) * cell), Vector2(PAD + float(cs) * cell, PAD + float(y) * cell), LINE, 1.0)
	var cells: Array = grid.cells
	var font := Fonts.cond(700, 0)
	var fs := Access.scaled(15 if cell >= 46.0 else 13)
	for i in cells.size():
		var c: Dictionary = cells[i]
		var foot := InvGeom.stack_rect(c, _size_fn, cell, PAD)
		var plate := foot.grow(-2.0)
		if revealed >= 0 and i >= revealed:
			_draw_unfound(plate, font)
			continue
		var d: Dictionary = InvApi.item(String(c.item))
		var wash: Color = InvIcons.res_color(String(d.get("res", "")))
		draw_rect(plate, Color(wash, 0.20))
		draw_rect(plate, Color(EDGE, 0.55), false, 1.5)
		InvIcons.draw_item(self, String(c.item), foot, int(c.rot), cell)
		if int(c.count) > 1:
			var txt := str(int(c.count))
			var at := Vector2(foot.end.x - 4.0, foot.end.y - 5.0)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs).x
			at.x -= w
			draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
			draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		if flash.has(i):
			draw_rect(plate, Color(ACCENT, 0.55 * clampf(float(flash[i]) / FLASH_S, 0.0, 1.0)))
		if i == held_index:
			draw_rect(plate, Color(0.02, 0.04, 0.035, 0.62))
		if i == hover_index and i != held_index:
			draw_rect(plate, Color(ACCENT, 0.95), false, 2.0)
	draw_rect(Rect2(Vector2(PAD, PAD), Vector2(float(cs) * cell, float(rs) * cell)), Color(EDGE, 0.5), false, 1.5)


## A stack that has not been found yet: its footprint, dark, with a question mark.
func _draw_unfound(plate: Rect2, font: Font) -> void:
	draw_rect(plate, Color(0.09, 0.13, 0.12, 0.96))
	draw_rect(plate, Color(INK3, 0.5), false, 1.5)
	var fs := int(minf(plate.size.x, plate.size.y) * 0.62)
	var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := font.get_ascent(fs)
	draw_string(font, plate.get_center() + Vector2(-w * 0.5, asc * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK3, 0.85))
