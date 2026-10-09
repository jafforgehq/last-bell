## The backpack window (INV-UI): her pack as a grid (8 by 4 cells by default), the equipment beside it (the shotgun with the rounds in the magazine and the shells in the pack, the melee swing),
## and one line of how to use it. A board in the HUD's own look (the dark green panel with the brass edge), built once by `inv_ui.gd` and only brought up to date when the sim's pack
## changed (`refresh`). It never takes a key and never pauses the game.
extends PanelContainer

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")
const InvGeom := preload("res://scripts/ui/inv_geom.gd")
const InvGridScript := preload("res://scripts/ui/inv_grid.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")

const EQUIP_H := 64.0

var ctl
var hud
var grid_ctl
var title: Label
var fill_label: Label
var close_button: Button
var equip
var reload_button: Button
var hint: Label
var _fill_text := ""


func setup(controller, hud_node, cell: float) -> void:
	ctl = controller
	hud = hud_node
	name = "InvPackWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _style())
	var col: VBoxContainer = hud._vbox(6)
	add_child(col)
	var head: HBoxContainer = hud._hbox(8)
	var badge := PackBadge.new()
	head.add_child(badge)
	title = hud._label("BACKPACK", Fonts.cond(700, 1), 15, hud.ACCENT)
	head.add_child(title)
	fill_label = hud._label("", Fonts.cond(700, 0), 15, hud.INK2)
	head.add_child(fill_label)
	head.add_child(hud._spacer())
	close_button = RadioKit.small_button(hud, "×", 26.0, 18)
	close_button.custom_minimum_size.x = 30.0
	close_button.pressed.connect(func(): ctl.close_pack())
	head.add_child(close_button)
	col.add_child(head)
	grid_ctl = InvGridScript.new()
	grid_ctl.name = "InvPackGrid"
	grid_ctl.setup(ctl, "pack", {"w": 8, "h": 4, "cells": []}, cell)
	col.add_child(grid_ctl)
	equip = Equip.new()
	equip.setup(hud, ctl)
	col.add_child(equip)
	var row: HBoxContainer = hud._hbox(8)
	hint = hud._label("", Fonts.sans(400), 13, hud.INK3)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.custom_minimum_size.x = 120
	row.add_child(hint)
	col.add_child(row)
	reload_button = RadioKit.small_button(hud, "Reload", 22.0, 13)
	reload_button.pressed.connect(func(): ctl.reload_pressed())
	equip.add_child(reload_button)
	set_texts()


func _style() -> StyleBox:
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 9
		st.content_margin_bottom = 10
	return st


## The words that name keys: read from the controls table so that they cannot disagree with it.
func set_texts() -> void:
	var tab := ControlsTable.key_text("inv")
	close_button.tooltip_text = "Close the backpack\nKey: %s, or Esc" % tab
	tooltip_text = ""
	hint.text = "Drag to move. %s turns it while you drag. Double-click moves it at once. Right-click for the menu." % ControlsTable.key_text("inv_rot")
	reload_button.tooltip_text = "Reload the shotgun from the shells in the pack\nKey: R"


func set_cell(cell: float) -> void:
	grid_ctl.set_cell(cell)
	equip.set_cell(cell)
	# the small window: the line of how-tos is the tooltips' and the Controls page's
	hint.visible = cell >= 44.0


## Each time the sim's pack changed (or the gun did): the grid, the fullness and the equipment.
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
	equip.refresh(sim, pack)
	reload_button.visible = equip.can_reload
	reload_button.disabled = not equip.can_reload_now
	equip._place_reload()


## The small pack drawn at the head of the window.
class PackBadge:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var ic := load("res://scripts/ui/inv_icons.gd")
		ic.draw_pack(self, Rect2(Vector2.ZERO, size), Color("#d2a94e"))


## The equipment: the weapon with its magazine and the shells that can fill it, and the melee swing (no item). Drawn, not laid out; one tooltip for each slot.
class Equip:
	extends Control

	const InvApi := preload("res://scripts/ui/inv_api.gd")
	const InvIcons := preload("res://scripts/ui/inv_icons.gd")
	const Fonts := preload("res://scripts/ui/fonts.gd")
	const Access := preload("res://scripts/access.gd")
	const INK := Color("#eeeadd")
	const INK2 := Color("#c1c5b5")
	const INK3 := Color("#a8ae9d")
	const ACCENT := Color("#f0c24a")
	const WARN := Color("#e8953a")
	const DANGER := Color("#f27f72")
	const BRASS := Color("#d2a94e")

	var hud
	var ctl
	var cell := 48.0
	var gun_name := "Pump shotgun"
	var mag := 0
	var cap := 0
	var reserve := 0
	var melee_only := false
	var can_reload := false
	var can_reload_now := false
	var reloading := false
	var _sig := ""

	func setup(hud_node, controller) -> void:
		hud = hud_node
		ctl = controller
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0.0, 64.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_cell(c: float) -> void:
		cell = c
		queue_redraw()

	func refresh(sim, pack: Dictionary) -> void:
		# (the rules say what she holds: `sim.inv.equipment()` = {"weapon": {name, mag, cap, reserve, reloading}, "melee": {name}})
		var w: Dictionary = InvApi.equipment(sim).get("weapon", {})
		var n := int(w.get("reserve", InvApi.units(pack, "ammo") if not pack.is_empty() else 0))
		var gm := int(w.get("mag", 0))
		var gc := int(w.get("cap", 0))
		var nm := String(w.get("name", "Pump shotgun"))
		var melee: bool = w.is_empty() or gc <= 0
		var rl: bool = float(w.get("reloading", 0.0)) > 0.0
		var k := Access.text_k()
		if not is_equal_approx(custom_minimum_size.y, 64.0 * k):
			custom_minimum_size.y = 64.0 * k    # (Large and Larger text: a taller slot)
			_sig = ""
		var sig := "%s|%d|%d|%d|%s|%s" % [nm, gm, gc, n, str(melee), str(rl)]
		if sig == _sig:
			return
		_sig = sig
		gun_name = nm
		mag = gm
		cap = gc
		reserve = n
		melee_only = melee
		reloading = rl
		can_reload = not melee and cap > 0
		can_reload_now = can_reload and mag < cap and reserve > 0 and not rl
		queue_redraw()

	func _slot_rects() -> Array:
		var w := size.x
		var gw := floorf((w - 8.0) * 0.64)
		return [Rect2(Vector2(0, 0), Vector2(gw, size.y)), Rect2(Vector2(gw + 8.0, 0), Vector2(w - gw - 8.0, size.y))]

	func _draw() -> void:
		var rs := _slot_rects()
		var font := Fonts.cond(700, 0)
		var small := Fonts.sans(500, 0)
		for r in rs:
			draw_rect(r, Color(0.035, 0.07, 0.06, 0.92))
			draw_rect(r, Color(BRASS, 0.5), false, 1.5)
		var g: Rect2 = rs[0]
		var k := Access.text_k()    # (the words are bigger under Large and Larger text: the slot is taller, and each line stands lower by as much)
		# the weapon
		draw_string(small, g.position + Vector2(8, 15.0 * k), "WEAPON", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.scaled(12), INK3)
		InvIcons.draw_gun(self, Rect2(g.position + Vector2(8, 18.0 * k + 2.0), Vector2(g.size.y * 0.92 / k, g.size.y - 24.0 * k)))
		var tx := g.position.x + g.size.y * 0.92 / k + 14.0
		var fs := Access.scaled(15)
		draw_string(font, Vector2(tx, g.position.y + 34.0 * k), gun_name, HORIZONTAL_ALIGNMENT_LEFT, g.end.x - tx - 6.0, fs, INK)
		if not melee_only:
			var low := mag <= maxi(1, ceili(float(cap) * 0.25))
			var mc: Color = (DANGER if mag <= 0 else (WARN if low else INK))
			var mt := "%d / %d" % [mag, cap]
			if Access.markers() and low:
				mt = ("!! " if mag <= 0 else "! ") + mt    # (Colour-blind markers: the amber and the red of the rounds are marks too, as on the gun's readout)
			var sfs := Access.scaled(20)
			draw_string(font, Vector2(tx, g.position.y + 57.0 * k), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, mc)
			var after := Vector2(tx + font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x + 8.0, g.position.y + 56.0 * k)
			draw_string(small, after, (("%d in the pack" % reserve) if reserve > 0 else "none in the pack") if not reloading else "reloading", HORIZONTAL_ALIGNMENT_LEFT, g.end.x - after.x - 4.0, Access.scaled(13), INK2 if reserve > 0 else DANGER)
		# the melee swing
		var m: Rect2 = rs[1]
		draw_string(small, m.position + Vector2(8, 15.0 * k), "MELEE", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.scaled(12), INK3)
		var mi := (m.size.y - 22.0 * k) / k
		InvIcons.draw_melee(self, Rect2(m.position + Vector2(6, 18.0 * k), Vector2(mi, mi)))
		draw_string(font, Vector2(m.position.x + mi + 4.0, m.position.y + 45.0 * k), "Swing", HORIZONTAL_ALIGNMENT_LEFT, m.end.x - (m.position.x + mi + 4.0) - 4.0, Access.scaled(15), INK)

	func _get_tooltip(at_position: Vector2) -> String:
		var rs := _slot_rects()
		if (rs[0] as Rect2).has_point(at_position):
			if melee_only:
				return "No gun in hand: only the swing"
			return "%s: %d in the magazine of %d, %d shells in the pack.\nA reload takes the shells from the pack.\nKey: R" % [gun_name, mag, cap, reserve]
		return "The swing: no item, no ammunition. A blow is quiet.\nKey: F"

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
			_place_reload()

	func _place_reload() -> void:
		for c in get_children():
			if c is Button:
				var rs := _slot_rects()
				var g: Rect2 = rs[0]
				var s: Vector2 = (c as Button).get_combined_minimum_size()
				(c as Button).size = s
				(c as Button).position = Vector2(g.end.x - s.x - 6.0, g.position.y + 4.0)
