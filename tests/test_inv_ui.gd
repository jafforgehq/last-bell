extends "res://tests/case.gd"
## INV-UI: the inventory's windows. The pure geometry (which cell a point is over, whether a held item fits, what it would join), the item table the windows draw from, the controls table's
## new rows, and the windows themselves (the pack, the container, the stash, the menu, the grid) on the real HUD with a stand-in controller. The staged game (`--inv=probe`,
## tools/inv_probe.gd) is the end-to-end check with real mouse and key events; these are the parts that need no game.

const Kit := preload("res://tests/hud_kit.gd")
const InvGeom := preload("res://scripts/ui/inv_geom.gd")
const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")
const InvGridScript := preload("res://scripts/ui/inv_grid.gd")
const InvPackWindow := preload("res://scripts/ui/inv_pack_window.gd")
const InvLootWindow := preload("res://scripts/ui/inv_loot_window.gd")
const InvStashWindow := preload("res://scripts/ui/inv_stash_window.gd")
const InvMenu := preload("res://scripts/ui/inv_menu.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")


## The footprints the geometry tests use (a bottle is 1 by 2, a jug 2 by 2, a medkit 2 by 1, the rest 1 by 1).
func _size(id: String, rot: int) -> Vector2i:
	var base := {"bottle": Vector2i(1, 2), "jug": Vector2i(2, 2), "medkit": Vector2i(2, 1)}.get(id, Vector2i(1, 1)) as Vector2i
	return Vector2i(base.y, base.x) if rot == 1 else base


func _cap(id: String) -> int:
	return 4 if id == "bandage" else 1


func _grid() -> Dictionary:
	return {"w": 8, "h": 4, "cells": [
		{"item": "bottle", "x": 0, "y": 0, "rot": 0, "count": 1},
		{"item": "jug", "x": 2, "y": 0, "rot": 0, "count": 1},
		{"item": "bandage", "x": 5, "y": 0, "rot": 0, "count": 3},
		{"item": "bandage", "x": 6, "y": 0, "rot": 0, "count": 4},
		{"item": "medkit", "x": 4, "y": 2, "rot": 0, "count": 1},
	]}


# ----------------------------------------------------------------------------- geometry --

func test_cell_at_finds_the_cell_under_a_point() -> void:
	eq(InvGeom.cell_at(Vector2(2.0 + 5.0, 2.0 + 5.0), 48.0, 8, 4, 2.0), Vector2i(0, 0), "the corner cell")
	eq(InvGeom.cell_at(Vector2(2.0 + 48.0 * 3.0 + 1.0, 2.0 + 48.0 * 2.0 + 47.0), 48.0, 8, 4, 2.0), Vector2i(3, 2), "a cell in the middle, near its far edge")
	eq(InvGeom.cell_at(Vector2(2.0 + 48.0 * 7.0 + 47.0, 2.0 + 48.0 * 3.0 + 47.0), 48.0, 8, 4, 2.0), Vector2i(7, 3), "the last cell")
	eq(InvGeom.cell_at(Vector2(1.0, 10.0), 48.0, 8, 4, 2.0), Vector2i(-1, -1), "left of the cells (the frame)")
	eq(InvGeom.cell_at(Vector2(2.0 + 48.0 * 8.0 + 1.0, 10.0), 48.0, 8, 4, 2.0), Vector2i(-1, -1), "past the last column")
	eq(InvGeom.cell_at(Vector2(10.0, 2.0 + 48.0 * 4.0 + 1.0), 48.0, 8, 4, 2.0), Vector2i(-1, -1), "past the last row")
	eq(InvGeom.cell_at(Vector2(41.0, 41.0), 40.0, 8, 4, 2.0), Vector2i(0, 0), "a 40 px cell has its own edge")
	eq(InvGeom.cell_at(Vector2(43.0, 43.0), 40.0, 8, 4, 2.0), Vector2i(1, 1), "and the next one begins at 42")


func test_stack_rect_and_index_at() -> void:
	var g := _grid()
	var r := InvGeom.stack_rect(g.cells[1], Callable(self, "_size"), 48.0, 2.0)
	eq(r, Rect2(Vector2(2.0 + 96.0, 2.0), Vector2(96.0, 96.0)), "the jug covers two cells each way")
	var sz := Callable(self, "_size")
	eq(InvGeom.index_at(g, sz, Vector2i(0, 1)), 0, "the second cell of the bottle")
	eq(InvGeom.index_at(g, sz, Vector2i(3, 1)), 1, "the far corner of the jug")
	eq(InvGeom.index_at(g, sz, Vector2i(1, 0)), -1, "an empty cell")
	eq(InvGeom.index_at(g, sz, Vector2i(5, 2), 4), -1, "the stack that is held does not count")
	eq(InvGeom.index_at(g, sz, Vector2i(5, 2)), 4, "and when it is not held it does")


func test_fit_says_free_blocked_or_outside() -> void:
	var g := _grid()
	var sz := Callable(self, "_size")
	eq(InvGeom.fit(g, sz, 0, 2, 1, 2), InvGeom.FREE, "a bottle under the bottle")
	eq(InvGeom.fit(g, sz, 1, 0, 1, 2), InvGeom.FREE, "a bottle between the bottle and the jug")
	eq(InvGeom.fit(g, sz, 1, 0, 2, 1), InvGeom.BLOCKED, "two wide runs into the jug")
	eq(InvGeom.fit(g, sz, 7, 3, 2, 1), InvGeom.OUTSIDE, "two wide at the last column is past the edge")
	eq(InvGeom.fit(g, sz, 0, 3, 1, 2), InvGeom.OUTSIDE, "two tall in the last row is past the edge")
	eq(InvGeom.fit(g, sz, -1, 0, 1, 1), InvGeom.OUTSIDE, "left of the grid")
	eq(InvGeom.fit(g, sz, 4, 2, 2, 1, 4), InvGeom.FREE, "the stack that is held does not block its own place")
	eq(InvGeom.fit(g, sz, 5, 2, 2, 1, 4), InvGeom.FREE, "and may move one cell along over its own cells")
	eq(InvGeom.fit(g, sz, 5, 2, 2, 1), InvGeom.BLOCKED, "while a stack that is not held does")


func test_target_joins_a_stack_that_has_room_and_never_itself() -> void:
	var g := _grid()
	var sz := Callable(self, "_size")
	var cap := Callable(self, "_cap")
	# a bandage (3) held, over the other stack of bandages with room? it is full (4): blocked
	var full := InvGeom.target(g, sz, cap, "bandage", 0, 3, Vector2i(6, 0), Vector2i(0, 0), 2)
	eq(full.state, InvGeom.BLOCKED, "a full stack takes nothing")
	# a single bandage held over the stack of three: it joins
	var join := InvGeom.target(g, sz, cap, "bandage", 0, 1, Vector2i(5, 0), Vector2i(0, 0))
	eq(join.state, InvGeom.MERGE, "a stack with room is joined")
	eq(join.index, 2, "which one")
	eq(Vector2i(join.x, join.y), Vector2i(5, 0), "at its own corner")
	# the stack held over its own place is not a merge with itself
	var self_t := InvGeom.target(g, sz, cap, "bandage", 0, 3, Vector2i(5, 0), Vector2i(0, 0), 2)
	eq(self_t.state, InvGeom.FREE, "a stack over itself is free (it only stays)")
	# a different thing over a stack is blocked, over free cells free
	eq(InvGeom.target(g, sz, cap, "bottle", 0, 1, Vector2i(5, 0), Vector2i(0, 0)).state, InvGeom.BLOCKED, "a bottle over bandages")
	eq(InvGeom.target(g, sz, cap, "bottle", 0, 1, Vector2i(7, 1), Vector2i(0, 0)).state, InvGeom.FREE, "a bottle on free cells")
	# held by its second cell: the corner is one cell up and left
	var held := InvGeom.target(g, sz, cap, "bottle", 0, 1, Vector2i(7, 3), Vector2i(0, 1))
	eq(Vector2i(held.x, held.y), Vector2i(7, 2), "the corner follows the cell it is held by")
	eq(held.state, InvGeom.FREE, "and fits there")
	# turned, the same bottle is two wide: held at the edge it does not fit
	eq(InvGeom.target(g, sz, cap, "bottle", 1, 1, Vector2i(7, 3), Vector2i(0, 0)).state, InvGeom.OUTSIDE, "turned over the last column: past the edge")


func test_a_turn_keeps_the_held_cell_inside_the_new_footprint() -> void:
	eq(InvGeom.turned_grab(Vector2i(0, 1), 2, 1), Vector2i(1, 0), "the second cell of a bottle becomes the second of two across")
	eq(InvGeom.turned_grab(Vector2i(0, 0), 2, 1), Vector2i(0, 0), "a corner stays a corner")
	eq(InvGeom.turned_grab(Vector2i(1, 0), 1, 2), Vector2i(0, 1), "and back")
	eq(InvGeom.turned_grab(Vector2i(1, 1), 2, 2), Vector2i(1, 1), "the far corner of a jug stays the far corner")
	eq(InvGeom.turned_grab(Vector2i(1, 1), 1, 1), Vector2i(0, 0), "clamped to a one cell item")


func test_the_cell_follows_the_window() -> void:
	eq(InvGeom.cell_for(Vector2(1280, 736)), 48.0, "1280 x 800")
	eq(InvGeom.cell_for(Vector2(1600, 900)), 48.0, "1920 x 1080 and 2560 x 1440")
	eq(InvGeom.cell_for(Vector2(1024, 640)), 40.0, "the smallest window")
	eq(InvGeom.cell_for(Vector2(1200, 660)), 40.0, "a short window")


func test_fullness_and_the_first_free_place() -> void:
	var g := _grid()
	var sz := Callable(self, "_size")
	var f := InvGeom.fullness(g, sz)
	eq(f, Vector2i(2 + 4 + 1 + 1 + 2, 32), "cells used and cells in all")
	eq(InvGeom.first_free(g, sz, 1, 1), Vector2i(1, 0), "the first free cell")
	eq(InvGeom.first_free(g, sz, 2, 2), Vector2i(6, 1), "the first place two by two fits (row by row: the second row, the last two columns)")
	var full := {"w": 2, "h": 1, "cells": [{"item": "bandage", "x": 0, "y": 0, "rot": 0, "count": 1}, {"item": "bandage", "x": 1, "y": 0, "rot": 0, "count": 1}]}
	eq(InvGeom.first_free(full, sz, 1, 1), Vector2i(-1, -1), "none in a full grid")


func test_rect_hit_names_the_first_rectangle() -> void:
	var rects := [Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10)]
	eq(InvGeom.rect_hit(rects, Vector2(7, 7)), 0, "the first of two that overlap")
	eq(InvGeom.rect_hit(rects, Vector2(12, 12)), 1, "the second")
	eq(InvGeom.rect_hit(rects, Vector2(30, 30)), -1, "none")


# -------------------------------------------------------------------------------- the items --

func test_every_item_has_a_picture_a_name_and_a_size() -> void:
	if not InvApi.available():
		return    # (this tree has the windows and not yet the rules: scripts/sim/inventory.gd)
	InvApi.reset()
	var defs := InvApi.defs()
	check(defs.size() >= 7, "the items of items.json are read (%d)" % defs.size())
	for id in defs:
		var d: Dictionary = defs[id]
		check(InvIcons.KNOWN.has(id), "%s has a picture of its own" % id)
		check(String(d.name) != "" and int(d.w) >= 1 and int(d.h) >= 1 and int(d.stack) >= 1, "%s has a name, a size and a stack" % id)
		check(String(d.desc) != "", "%s says what it is" % id)
	eq(InvApi.size_of("water_bottle"), Vector2i(1, 2), "a bottle is one cell wide and two tall")
	eq(InvApi.size_of("water_bottle", 1), Vector2i(2, 1), "turned it is two wide")
	eq(InvApi.size_of("water_bottle", true), Vector2i(2, 1), "a bool turn does the same")
	eq(InvApi.item("no_such_thing").name, "No Such Thing", "an unknown id is named after itself")


func test_the_chip_counts_cells_not_stacks() -> void:
	if not InvApi.available():
		return
	var pk := InvApi.make_grid(8, 4)
	InvApi.place(pk, "shells", 24, 0, 0)
	InvApi.place(pk, "water_jug", 1, 2, 0)
	InvApi.place(pk, "medkit", 1, 0, 2)
	eq(InvApi.used_cells(pk), 1 + 4 + 2, "one cell, four, two")
	eq(InvApi.cell_count(pk), 32, "of thirty-two")


# ------------------------------------------------------------------------- the controls --

func test_the_backpack_rows_are_in_the_controls_table() -> void:
	eq(ControlsTable.key_text("inv"), "Tab or I", "the pack's keys read as words")
	eq(ControlsTable.key_text("inv_take"), "Space or Enter", "and take all")
	eq(ControlsTable.key_text("inv_rot"), "R", "and the turn")
	eq(ControlsTable.key_text("nothing"), "", "an id that is none")
	var titles: Array = []
	for g in ControlsTable.groups(false):
		titles.append(String(g.title))
		for r in g.rows:
			check(String(r.keys) != "" and String(r.what) != "", "a row of %s has keys and words" % g.title)
	check(titles.has("The backpack"), "the Controls page has a group for the backpack")
	var hud_text := ""
	for g in ControlsTable.hud_groups(false):
		for e in g[2]:
			hud_text += " " + String(e[0]) + " " + String(e[1])
	check(hud_text.contains("Tab") and hud_text.contains("Backpack"), "the help panel names the key")
	# Tab was a key of nothing in the town: only the pack's own row names it now
	for g in ControlsTable.groups(false):
		for r in g.rows:
			check(not String(r.keys).split(" ").has("Tab") or String(r.get("id", "")) == "inv", "only the pack row names Tab (%s)" % String(r.keys))


# ------------------------------------------------------------------------------ the windows --

## A stand-in for the controller (`inv_ui.gd`): it records what the windows ask of it.
class FakeCtl:
	extends RefCounted
	var calls: Array = []
	var tip := "tip"

	func grid_input(_g, _ev) -> void:
		calls.append("grid_input")

	func grid_exit(_g) -> void:
		calls.append("grid_exit")

	func tip_text(_g, _at) -> String:
		return tip

	func close_pack() -> void:
		calls.append("close_pack")

	func close_loot() -> void:
		calls.append("close_loot")

	func close_stash() -> void:
		calls.append("close_stash")

	func reload_pressed() -> void:
		calls.append("reload")

	func take_all_pressed() -> void:
		calls.append("take_all")

	func deposit_all_pressed() -> void:
		calls.append("deposit_all")

	func withdraw_pressed(res: String, n: int) -> void:
		calls.append("withdraw %s %d" % [res, n])

	func menu_pick(id: String) -> void:
		calls.append("pick " + id)


func _hud_ctx() -> Dictionary:
	return Kit.build(1280, 800)


func test_the_pack_window_says_how_full_the_pack_is() -> void:
	if not InvApi.available():
		return
	var ctx := _hud_ctx()
	var ctl := FakeCtl.new()
	var w = InvPackWindow.new()
	w.setup(ctl, ctx.hud, 48.0)
	ctx.holder.add_child(w)
	var pk := InvApi.make_grid(8, 4)
	InvApi.place(pk, "shells", 24, 0, 0)
	InvApi.place(pk, "water_jug", 1, 2, 0)
	w.refresh(ctx.sim, pk, true)
	await Kit.settle()
	eq(w.fill_label.text, "5 / 32", "cells used of all")
	eq(w.grid_ctl.cols(), 8, "eight columns")
	eq(w.grid_ctl.rows(), 4, "four rows")
	eq(w.grid_ctl.custom_minimum_size, Vector2(8.0 * 48.0 + 4.0, 4.0 * 48.0 + 4.0), "the grid is as wide as its cells")
	w.set_cell(40.0)
	eq(w.grid_ctl.custom_minimum_size, Vector2(8.0 * 40.0 + 4.0, 4.0 * 40.0 + 4.0), "and as small as the small window wants")
	check(w.get_combined_minimum_size().x < 400.0, "a window of 40 px cells is under 400 px wide (%s)" % str(w.get_combined_minimum_size()))
	w.close_button.pressed.emit()
	eq(ctl.calls, ["close_pack"], "the cross asks the controller to put it away")
	check(w.close_button.tooltip_text.contains("Tab or I"), "its tooltip names the keys of the table")
	Kit.free_all(ctx)


func test_the_loot_window_shows_what_is_found_and_what_is_not() -> void:
	if not InvApi.available():
		return
	var ctx := _hud_ctx()
	var ctl := FakeCtl.new()
	var w = InvLootWindow.new()
	w.setup(ctl, ctx.hud, 48.0)
	ctx.holder.add_child(w)
	var g := InvApi.make_grid(4, 3)
	InvApi.place(g, "canned_food", 2, 0, 0)
	InvApi.place(g, "water_bottle", 1, 1, 0)
	InvApi.place(g, "bandage", 2, 2, 0)
	w.show_container({"id": "c1", "name": "kitchen counter", "grid": g, "revealed": 1})
	eq(w.title.text, "KITCHEN COUNTER", "the container's name")
	eq(w.status.text, "Searching... 1 of 3 found", "while it is being searched")
	eq(w.grid_ctl.revealed, 1, "one stack is shown, the others are question marks")
	check(not w.take_button.disabled, "Take all can take what is found")
	w.show_container({"id": "c1", "name": "kitchen counter", "grid": g, "revealed": 3})
	eq(w.status.text, "3 found", "when all are found")
	eq(w.grid_ctl.revealed, -1, "every stack is shown")
	check(w.grid_ctl.flash.size() <= 2, "the stacks found since the last look glow (a short while, none under Reduce motion)")
	w.show_container({"id": "c1", "name": "kitchen counter", "grid": g, "revealed": 0})
	check(w.take_button.disabled, "with nothing found there is nothing to take")
	w.close_button.pressed.emit()
	eq(ctl.calls, ["close_loot"], "the cross asks the controller to shut the container")
	check(w.take_button.tooltip_text.contains("Space or Enter"), "Take all names its keys from the controls table")
	Kit.free_all(ctx)


func test_the_stash_window_follows_the_stores() -> void:
	var ctx := _hud_ctx()
	var ctl := FakeCtl.new()
	var w = InvStashWindow.new()
	w.setup(ctl, ctx.hud)
	ctx.holder.add_child(w)
	w.refresh({"ammo": 46, "food": 12, "water": 0, "meds": 6, "scrap": 40}, true)
	eq(w.rows.ammo.count.text, "46", "the ammo")
	eq(w.rows.scrap.count.text, "40", "the scrap")
	check(not (w.rows.ammo.buttons[0] as Button).disabled, "an ammo button can take a round out")
	check((w.rows.water.buttons[0] as Button).disabled, "water is gone: its buttons are off")
	eq((w.rows.scrap.buttons as Array).size(), 0, "scrap is never carried: it has no buttons")
	check(not w.deposit_button.disabled, "Deposit all is on while the pack holds something")
	w.refresh({"ammo": 40, "food": 12, "water": 3, "meds": 6, "scrap": 40}, false)
	eq(w.rows.ammo.count.text, "40", "the numbers follow the stores as they move")
	check(w.deposit_button.disabled, "and off when the pack holds nothing for them")
	(w.rows.food.buttons[1] as Button).pressed.emit()
	(w.rows.meds.buttons[2] as Button).pressed.emit()
	eq(ctl.calls, ["withdraw food 5", "withdraw meds -1"], "the buttons ask for 5 and for all")
	Kit.free_all(ctx)


func test_the_menu_lists_what_can_be_done_and_greys_the_rest() -> void:
	var ctx := _hud_ctx()
	var ctl := FakeCtl.new()
	var m = InvMenu.new()
	m.setup(ctl, ctx.hud)
	ctx.holder.add_child(m)
	m.open_for([["Eat", "use", false, "Not yet"], ["Split in half", "split_half", true, ""], ["Drop", "drop", true, ""]], Vector2(1270, 790), Vector2(1280, 800))
	await Kit.settle()
	check(m.visible, "the menu is up")
	eq(m.entries, [["Eat", "use"], ["Split in half", "split_half"], ["Drop", "drop"]], "its entries")
	var rect := m.get_global_rect()
	check(rect.end.x <= 1280.0 and rect.end.y <= 800.0, "kept inside the window when opened at its corner (%s)" % str(rect))
	var buttons: Array = []
	for c in m.box.get_children():
		buttons.append(c)
	check((buttons[0] as Button).disabled and (buttons[0] as Button).tooltip_text == "Not yet", "a thing that cannot be done is grey and says why")
	(buttons[2] as Button).pressed.emit()
	eq(ctl.calls, ["pick drop"], "a press goes to the controller")
	m.close()
	check(not m.visible, "closed")
	Kit.free_all(ctx)


func test_a_grid_finds_the_stack_under_the_pointer_and_hides_what_is_not_found() -> void:
	if not InvApi.available():
		return
	var ctl := FakeCtl.new()
	var g = InvGridScript.new()
	var grid := InvApi.make_grid(4, 3)
	InvApi.place(grid, "canned_food", 2, 0, 0)
	InvApi.place(grid, "water_bottle", 1, 1, 0)
	g.setup(ctl, "loot", grid, 48.0)
	g.revealed = 1
	eq(g.index_at(Vector2(2.0 + 10.0, 2.0 + 10.0)), 0, "the can")
	eq(g.index_at(Vector2(2.0 + 60.0, 2.0 + 60.0), true), -1, "the bottle is not found yet: nothing to pick up")
	eq(g.index_at(Vector2(2.0 + 60.0, 2.0 + 60.0), false), 1, "but it is there for the tooltip's own question")
	eq(g._get_tooltip(Vector2(5, 5)), "tip", "a tooltip is asked of the controller")
	g.set_hover(0)
	eq(g.hover_index, 0, "the pointer's stack")
	g.free()
