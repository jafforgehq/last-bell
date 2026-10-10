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
const InvDoll := preload("res://scripts/ui/inv_doll.gd")
const InvUi := preload("res://scripts/ui/inv_ui.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")
const Helpers := preload("res://tests/helpers.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


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
	eq(InvGeom.cell_for(Vector2(1280, 720)), 34.0, "1280 x 720")
	eq(InvGeom.cell_for(Vector2(1280, 736)), 34.0, "1280 x 800")
	eq(InvGeom.cell_for(Vector2(1600, 900)), 34.0, "1920 x 1080 and 2560 x 1440")
	eq(InvGeom.cell_for(Vector2(1024, 640)), 32.0, "the smallest window")
	eq(InvGeom.cell_for(Vector2(1200, 660)), 32.0, "a short window")
	check(InvGeom.CELL_SMALL >= 32.0 and InvGeom.CELL <= 36.0, "a cell is 32 to 36 points: the pictures are drawn for that")


func test_the_budget_counts_the_block_the_windows_make() -> void:
	var vp := Vector2(1280, 720)
	var pack := Rect2(Vector2(10, 100), Vector2(450, 180))
	var under := Rect2(Vector2(10, 286), Vector2(420, 120))
	var b := InvGeom.budget_of([pack, under], vp)
	near(float(b.w), 450.0 / 1280.0, 0.0001, "the block is as wide as its widest window")
	near(float(b.h), 306.0 / 720.0, 0.0001, "and as tall as the two with the gap")
	near(float(b.area), (450.0 * 180.0 + 420.0 * 120.0) / (1280.0 * 720.0), 0.0001, "and the windows' own areas are counted for the screen")
	check(InvGeom.within_budget([pack, under], vp), "a pack with a window under it is inside the budget")
	var beside := Rect2(Vector2(466, 100), Vector2(420, 120))
	check(not InvGeom.within_budget([pack, beside], vp), "the same two side by side are 886 points, 69 percent of the width: over")
	check(not InvGeom.within_budget([pack, Rect2(Vector2(10, 290), Vector2(450, 400))], vp), "a block taller than 55 percent of the height is over")
	check(InvGeom.within_budget([], vp), "no window takes nothing")


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
		check(InvIcons.has_region(InvIcons.picture_of(String(id), 1)) and InvIcons.picture_of(String(id), 1) != "unknown", "%s has a picture in the atlas" % id)
		var pr := InvIcons.region(InvIcons.picture_of(String(id), 1))
		check(pr.size.x >= float(d.w) * 128.0 - 0.5 and pr.size.y >= float(d.h) * 128.0 - 0.5, "%s is drawn at 128 px for each cell of its footprint (%s)" % [id, str(pr.size)])
		check(String(d.name) != "" and int(d.w) >= 1 and int(d.h) >= 1 and int(d.stack) >= 1, "%s has a name, a size and a stack" % id)
		check(String(d.desc) != "", "%s says what it is" % id)
	eq(InvApi.size_of("water_bottle"), Vector2i(1, 2), "a bottle is one cell wide and two tall")
	eq(InvApi.size_of("water_bottle", 1), Vector2i(2, 1), "turned it is two wide")
	eq(InvApi.size_of("water_bottle", true), Vector2i(2, 1), "a bool turn does the same")
	eq(InvApi.item("no_such_thing").name, "No Such Thing", "an unknown id is named after itself")


func test_the_atlas_holds_every_picture_the_windows_ask_for() -> void:
	var tex := InvIcons.texture()
	check(tex != null, "the atlas is imported (assets/ui/inv/inv_icons.png)")
	if tex == null:
		return
	for name in ["shell", "shells", "shell_box", "canned_food", "ration_pack", "water_bottle", "water_jug", "bandage", "medkit", "unknown", "pump_shotgun", "melee", "pack", "slot", "slot_on", "slot_off", "glow", "ruth"]:
		var r := InvIcons.region(name)
		check(r.size.x > 0.0 and r.size.y > 0.0, "%s is in the table" % name)
		check(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= float(tex.get_width()) and r.end.y <= float(tex.get_height()), "%s lies inside the atlas (%s of %s)" % [name, str(r), str(tex.get_size())])
	# the pictures do not touch: a gutter of 8 pixels at least between any two (the mipmaps would blend neighbours)
	var names := InvIcons.region_names()
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(not InvIcons.region(String(names[i])).grow(8.0).intersects(InvIcons.region(String(names[j]))), "%s and %s keep a gutter between them" % [names[i], names[j]])
	var bytes := FileAccess.get_file_as_bytes(InvIcons.ATLAS).size()
	check(bytes > 0 and bytes < 450000, "the atlas stays small: the web build grows by at most half a megabyte (%d bytes)" % bytes)
	# loose shells are one, a few, or a box's worth
	eq(InvIcons.picture_of("shells", 1), "shell", "one shell")
	eq(InvIcons.picture_of("shells", 5), "shells", "a few")
	eq(InvIcons.picture_of("shells", 24), "shell_box", "a box's worth")
	eq(InvIcons.picture_of("water_bottle", 1), "water_bottle", "every other item has its own")
	eq(InvIcons.picture_of("no_such_thing", 1), "unknown", "and an item that is none is a box with a question mark")


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
	w.setup(ctl, ctx.hud, 34.0)
	ctx.holder.add_child(w)
	var pk := InvApi.make_grid(8, 4)
	InvApi.place(pk, "shells", 24, 0, 0)
	InvApi.place(pk, "water_jug", 1, 2, 0)
	w.refresh(ctx.sim, pk, true)
	await Kit.settle()
	eq(w.fill_label.text, "5 / 32", "cells used of all")
	eq(w.grid_ctl.cols(), 8, "eight columns")
	eq(w.grid_ctl.rows(), 4, "four rows")
	eq(w.grid_ctl.custom_minimum_size, Vector2(8.0 * 34.0 + 4.0, 4.0 * 34.0 + 4.0), "the grid is as wide as its cells")
	w.set_cell(32.0)
	eq(w.grid_ctl.custom_minimum_size, Vector2(8.0 * 32.0 + 4.0, 4.0 * 32.0 + 4.0), "and as small as the small window wants")
	check(w.get_combined_minimum_size().x < 450.0, "a window of 32 px cells is under 450 points wide (%s)" % str(w.get_combined_minimum_size()))
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
	g.setup(ctl, "loot", grid, 34.0)
	g.revealed = 1
	eq(g.index_at(Vector2(2.0 + 10.0, 2.0 + 10.0)), 0, "the can")
	eq(g.index_at(Vector2(2.0 + 60.0, 2.0 + 60.0), true), -1, "the bottle is not found yet: nothing to pick up")
	eq(g.index_at(Vector2(2.0 + 60.0, 2.0 + 60.0), false), 1, "but it is there for the tooltip's own question")
	eq(g._get_tooltip(Vector2(5, 5)), "tip", "a tooltip is asked of the controller")
	g.set_hover(0)
	eq(g.hover_index, 0, "the pointer's stack")
	g.free()


# ----------------------------------------------------------------------------- INV2: the layout --

func _vp_of(width: int, height: int) -> Vector2:
	# the interface's own points at a window size (the HUD scales its points with the window: 1.2 at 1920 x 1080, 1.6 at 2560 x 1440)
	var s := 1.0
	if width >= 2400:
		s = 1.6
	elif width >= 1800:
		s = 1.2
	return Vector2(float(width) / s, float(height) / s)


func test_the_windows_are_small_and_stay_inside_the_window_budget_at_every_size() -> void:
	if not InvApi.available():
		return
	for size in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1024, 640)]:
		var vp := _vp_of(size.x, size.y)
		var ctx := Kit.build(int(vp.x), int(vp.y))
		var ctl := FakeCtl.new()
		var cell := InvGeom.cell_for(vp)
		var pack = InvPackWindow.new()
		pack.setup(ctl, ctx.hud, cell)
		var loot = InvLootWindow.new()
		loot.setup(ctl, ctx.hud, cell)
		var stash = InvStashWindow.new()
		stash.setup(ctl, ctx.hud)
		for w in [pack, loot, stash]:
			ctx.holder.add_child(w)
		stash.refresh({"ammo": 46, "food": 12, "water": 3, "meds": 6, "scrap": 40}, true)
		await Kit.settle()
		var ps: Vector2 = pack.get_combined_minimum_size()
		var ls: Vector2 = loot.get_combined_minimum_size()
		var ss: Vector2 = stash.get_combined_minimum_size()
		var label := "%dx%d (%s points)" % [size.x, size.y, str(vp)]
		var area := ps.x * ps.y / (vp.x * vp.y)
		check(ps.x <= 0.45 * vp.x and ps.y <= 0.55 * vp.y, "the pack alone is inside 45 x 55 percent at %s: %s" % [label, str(ps)])
		check(area <= 0.14, "the pack takes %.1f percent of the screen at %s" % [area * 100.0, label])
		if size == Vector2i(1280, 720):
			check(area <= 0.10, "at 1280 x 720 the pack is about a tenth of the screen or less (%.1f percent, %s; it was 16 percent)" % [area * 100.0, str(ps)])
			check(cell >= 32.0 and cell <= 36.0, "with cells of 32 to 36 points")
		# the second window is put against the first (under it, left edges level): the block stays inside the budget
		var under_loot := [Rect2(Vector2.ZERO, ps), Rect2(Vector2(0.0, ps.y + 6.0), ls)]
		var under_stash := [Rect2(Vector2.ZERO, ps), Rect2(Vector2(0.0, ps.y + 6.0), ss)]
		check(InvGeom.within_budget(under_loot, vp), "the pack with the loot window under it is inside the budget at %s: %s" % [label, str(InvGeom.budget_of(under_loot, vp))])
		check(InvGeom.within_budget(under_stash, vp), "the pack with the stash panel under it is inside the budget at %s: %s" % [label, str(InvGeom.budget_of(under_stash, vp))])
		check(ls.x <= ps.x and ss.x <= ps.x + 1.0, "neither is wider than the pack at %s (%s, %s, %s)" % [label, str(ps), str(ls), str(ss)])
		check(InvGeom.within_area([Rect2(Vector2.ZERO, ps)], vp), "the pack alone is inside 17 percent of the screen at %s" % label)
		if size != Vector2i(1024, 640):
			# (the smallest window: the pack is 12 percent of it, and a second window cannot be had for the five that are left)
			check(InvGeom.within_area(under_loot, vp) and InvGeom.within_area(under_stash, vp), "and so is each pair, by area, at %s: %s, %s" % [label, str(InvGeom.budget_of(under_loot, vp)), str(InvGeom.budget_of(under_stash, vp))])
		Kit.free_all(ctx)


func test_the_doll_lays_out_four_quick_slots_on_the_belt_and_names_what_each_holds() -> void:
	var ctl := FakeCtl.new()
	var d = InvDoll.new()
	d.setup(ctl)
	for i in InvDoll.SLOTS:
		var r := InvDoll.slot_rect(i)
		check(r.size.x >= 26.0 and r.size.y >= 26.0, "slot %d is at least 26 points square (%s)" % [i, str(r.size)])
		check(Rect2(Vector2.ZERO, Vector2(InvDoll.W, InvDoll.H)).encloses(r), "slot %d is inside the doll" % i)
		check(not InvDoll.WEAPON.intersects(r) and not InvDoll.MELEE.intersects(r), "slot %d does not cover the weapon's or the swing's slot" % i)
		eq(d.quick_at(r.get_center()), i, "the middle of slot %d is slot %d" % [i, i])
		if i > 0:
			check(not InvDoll.slot_rect(i - 1).intersects(r), "slot %d and the one before it do not touch" % i)
	eq(d.quick_at(Vector2(2.0, 2.0)), -1, "a corner of the doll is no slot")
	check(not InvDoll.WEAPON.intersects(InvDoll.MELEE), "the weapon's and the swing's slots are apart")
	d.quick = [
		{"id": "", "count": 0, "state": "empty", "name": ""},
		{"id": "bandage", "count": 3, "state": "ready", "name": "Bandage"},
		{"id": "canned_food", "count": 8, "state": "soon", "name": "Canned food"},
		{"id": "water_bottle", "count": 0, "state": "off", "name": "Water bottle"},
	]
	check(d.quick_tip(0).contains("empty") and d.quick_tip(0).contains("Key: 1"), "an empty slot says so and names its key")
	check(d.quick_tip(1).contains("Bandage x 3") and d.quick_tip(1).contains("press 2"), "a ready slot says what it holds and how to use it")
	check(d.quick_tip(2).to_lower().contains("needs: coming soon"), "food and drink are greyed with 'needs: coming soon'")
	check(d.quick_tip(3).contains("None in the pack"), "a slot whose item has run out says so")
	d.free()


# ------------------------------------------------------------------------ INV2: the quick slots --

## A stand-in for `scripts/main.gd` as the inventory part sees it.
class FakeMain:
	extends RefCounted
	var hud
	var sim
	var menu_open := false
	var zoom_px := 32.0
	var town = null

	func view_pos(p) -> Vector2:
		return Vector2(p.x, p.y)

	func _tile_to_screen(v: Vector2) -> Vector2:
		return v * zoom_px

	func _vp() -> Vector2:
		return hud.size


## A town run with the data's start pack, the HUD of the tests over it and the inventory part built on a stand-in main.
func _ui_game(width: int = 1280, height: int = 720) -> Dictionary:
	var ctx := Kit.build(width, height)
	await Kit.settle()
	var tg := Helpers.town_game(1, {"home": true})
	var sim = tg.sim
	sim.field.pause_wake = true
	var start: Dictionary = OneHouse.data().start
	for k in start.stock:
		sim.stock[String(k)] = float(start.stock[k])
	sim.inv.begin(start.pack)
	sim.events.clear()
	var fm := FakeMain.new()
	fm.hud = ctx.hud
	fm.sim = sim
	var ui := InvUi.new()
	ui.on_ready(fm)
	return {"ctx": ctx, "tg": tg, "sim": sim, "fm": fm, "ui": ui}


func _free_ui_game(g: Dictionary) -> void:
	Kit.free_all(g.ctx)
	g.tg.world.free()


func _key(code: Key, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


func test_the_belt_starts_with_what_she_lives_on_and_a_kind_sits_on_one_slot_only() -> void:
	if not InvApi.available():
		return
	var g := await _ui_game()
	var sim = g.sim
	eq(InvApi.quick(sim), ["bandage", "canned_food", "water_bottle", ""], "the belt starts with a bandage, a tin and a bottle")
	check(InvApi.set_quick(sim, 3, "bandage"), "a bandage may go on slot 4")
	eq(InvApi.quick(sim), ["", "canned_food", "water_bottle", "bandage"], "and leaves slot 1: a kind is on one slot only")
	check(not InvApi.set_quick(sim, 0, "shells"), "shells have no use: they do not go on the belt")
	check(not InvApi.set_quick(sim, 4, "bandage") and not InvApi.set_quick(sim, -1, "bandage"), "there is no slot 5")
	check(not InvApi.set_quick(sim, 0, "no_such_thing"), "an item that is none does not either")
	check(InvApi.set_quick(sim, 3, ""), "a slot can be emptied")
	eq(InvApi.quick(sim), ["", "canned_food", "water_bottle", ""], "and is empty")
	check(InvApi.quick_ok("medkit") and InvApi.quick_ok("ration_pack") and not InvApi.quick_ok("shells"), "anything with a use may go on it")
	_free_ui_game(g)


func test_an_item_is_put_on_a_quick_slot_by_a_drop_or_by_its_menu() -> void:
	if not InvApi.available():
		return
	var g := await _ui_game()
	var sim = g.sim
	var ui = g.ui
	ui.open_pack()
	await Kit.settle()
	var pk := InvApi.pack(sim)
	InvApi.place(pk, "medkit", 1, 6, 3)
	ui._after_change()
	await Kit.settle()
	var gc = ui.pack_win.grid_ctl
	var idx := InvApi.first_stack(pk, "medkit")
	check(idx >= 0, "a medkit is in the pack")
	# held over the empty fourth slot: green, and the drop puts it there
	var slot_rect: Rect2 = ui.pack_win.doll.slot_global_rect(3)
	ui.begin_drag(gc, idx, gc.get_global_rect().position + gc.rect_of(idx).get_center())
	ui.drag_move(slot_rect.get_center())
	eq(String(ui.drag.target.get("over", "")), "quick", "over a quick slot")
	eq(int(ui.drag.target.get("slot", -1)), 3, "the fourth")
	eq(String(ui.drag.target.state), InvGeom.FREE, "a medkit may go there: the frame is green")
	ui.drop_at(slot_rect.get_center())
	eq(InvApi.quick(sim)[3], "medkit", "the medkit is on slot 4")
	check(InvApi.first_stack(pk, "medkit") >= 0, "and is still in the pack: the slot names a kind, it takes nothing out")
	check(ui.last_toast.contains("Quick slot 4"), "it says so (%s)" % ui.last_toast)
	# shells do not go on it: red, and nothing changes
	var si := InvApi.first_stack(pk, "shells")
	ui.begin_drag(gc, si, gc.get_global_rect().position + gc.rect_of(si).get_center())
	ui.drag_move(slot_rect.get_center())
	eq(String(ui.drag.target.state), InvGeom.BLOCKED, "shells over a quick slot: the frame is red")
	ui.drop_at(slot_rect.get_center())
	eq(InvApi.quick(sim)[3], "medkit", "nothing changed")
	# the item's menu: onto the first empty slot
	check(InvApi.set_quick(sim, 3, ""), "slot 4 is empty again")
	InvApi.auto_add(pk, "ration_pack", 1)
	var ri := InvApi.first_stack(pk, "ration_pack")
	check(ri >= 0, "a ration pack is in the pack")
	ui._open_menu(gc, ri, Vector2(100, 100))
	var ids: Array = []
	for e in ui.menu.entries:
		ids.append(String(e[1]))
	check(ids.has("quick"), "the menu of a ration pack offers a quick slot (%s)" % str(ids))
	ui.menu_pick("quick")
	eq(InvApi.quick(sim)[3], "ration_pack", "it went to the first empty slot")
	ui.menu_pick("quick")
	ui.close_all()
	_free_ui_game(g)


func test_keys_1_to_4_use_the_quick_slots_and_shift_keeps_the_speeds() -> void:
	if not InvApi.available():
		return
	var g := await _ui_game()
	var sim = g.sim
	var ui = g.ui
	var me = sim.avatar.player()
	var pk := InvApi.pack(sim)
	# 1: a bandage, and she bleeds
	me.bleeding = 1.0
	var had := InvApi.count_of(pk, "bandage")
	var n0: int = ui.toast_count
	check(ui.on_key(_key(KEY_1)), "the key 1 is the belt's")
	eq(ui.last_toast, "Bandaging", "slot 1 bandages the wound")
	check(sim.uses.in_session("selfcare", "bandage"), "through the rules' own use")
	Helpers.run(sim, 12.0)
	check(InvApi.count_of(pk, "bandage") < had, "a bandage was used up (%d of %d left)" % [InvApi.count_of(pk, "bandage"), had])
	# 1 again with no wound: the rules say why
	me.bleeding = 0.0
	ui.on_key(_key(KEY_1))
	check(ui.last_toast.contains("not bleeding"), "no wound: the rules say so (%s)" % ui.last_toast)
	# 2 and 3: a tin and a bottle are greyed until the needs step
	var cans := InvApi.count_of(pk, "canned_food")
	check(ui.on_key(_key(KEY_2)), "the key 2 is the belt's")
	check(ui.last_toast.to_lower().contains("needs are coming soon"), "a tin: needs are coming soon (%s)" % ui.last_toast)
	check(ui.on_key(_key(KEY_3)) and ui.last_toast.to_lower().contains("coming soon"), "a bottle too")
	eq(InvApi.count_of(pk, "canned_food"), cans, "and nothing was eaten")
	# 4: empty
	check(ui.on_key(_key(KEY_4)), "the key 4 is the belt's")
	check(ui.last_toast.contains("Quick slot 4 is empty"), "an empty slot says so (%s)" % ui.last_toast)
	# the keypad's digits do the same
	var n1: int = ui.toast_count
	check(ui.on_key(_key(KEY_KP_4)), "the keypad's 4 too")
	check(ui.toast_count == n1 + 1, "it spoke")
	# Shift and a digit are the speeds: the part leaves them alone
	var n2: int = ui.toast_count
	check(not ui.on_key(_key(KEY_1, true)) and not ui.on_key(_key(KEY_2, true)) and not ui.on_key(_key(KEY_3, true)), "Shift 1, 2 and 3 are not the belt's")
	eq(ui.toast_count, n2, "and say nothing")
	# a menu, a page or the end of the run has the keys
	g.fm.menu_open = true
	check(not ui.on_key(_key(KEY_1)), "with the menu up the digits are not the belt's")
	g.fm.menu_open = false
	check(ui.toast_count > n0, "the belt spoke through the toasts")
	_free_ui_game(g)


func test_the_belt_is_saved_and_loaded_and_an_old_save_has_an_empty_one() -> void:
	if not InvApi.available():
		return
	var g := await _ui_game()
	var sim = g.sim
	InvApi.set_quick(sim, 0, "medkit")
	InvApi.set_quick(sim, 3, "bandage")
	var want := InvApi.quick(sim)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(data.modules.inv.quick, want, "the belt is in the save")
	var f := Helpers.town_game(1, {"home": true})
	check(SaveGame.apply(f.sim, data), "the save is read")
	eq(InvApi.quick(f.sim), want, "and the belt comes back as it was")
	eq(SaveGame.town_compat(data), "", "the town's version is this build's: the belt changed nothing a save means")
	# a save that has no belt (made before the quick slots) loads with an empty one
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	old.modules.inv.erase("quick")
	var h := Helpers.town_game(1, {"home": true})
	check(SaveGame.apply(h.sim, old), "a save from before the belt is read")
	eq(InvApi.quick(h.sim), ["", "", "", ""], "with an empty belt")
	# a bad entry is dropped, the rest kept
	var bad: Dictionary = JSON.parse_string(JSON.stringify(data))
	bad.modules.inv.quick = ["no_such_thing", "bandage", 7, "water_jug", "extra"]
	var k := Helpers.town_game(1, {"home": true})
	check(SaveGame.apply(k.sim, bad), "a belt with a bad entry is read")
	eq(InvApi.quick(k.sim)[1], "bandage", "the good one is kept")
	eq(InvApi.quick(k.sim)[0], "", "the item that is none is not")
	f.world.free()
	h.world.free()
	k.world.free()
	_free_ui_game(g)


func test_the_speeds_are_shift_1_2_3_in_the_one_house_and_the_digits_answer_the_cards_first() -> void:
	if not InvApi.available():
		return
	var tg := Helpers.town_game(1, {"home": true})
	var m = load("res://scripts/main.gd").new()
	m.sim = tg.sim
	check(m.wheel_simple(), "this is the One House")
	check(not m._speed_key(_key(KEY_1)) and not m._speed_key(_key(KEY_3)), "a plain digit is no speed there (it is a quick slot)")
	check(m._speed_key(_key(KEY_1, true)) and m._speed_key(_key(KEY_2, true)) and m._speed_key(_key(KEY_3, true)), "Shift and 1, 2, 3 are the speeds")
	m.sim = null
	check(m._speed_key(_key(KEY_1)), "everywhere else a plain digit is still a speed")
	m.free()
	tg.world.free()
	# the rescue card answers 1 2 3 and keeps 4 to 9 from the belt while it is up; with no card up it leaves every key alone
	var rc = load("res://scripts/ui/rescue_card.gd").new()
	check(not rc.on_key(_key(KEY_4)), "no card up: the digit goes on")
	rc.shown = "someone"
	check(rc.on_key(_key(KEY_4)) and rc.on_key(_key(KEY_9)), "a card up: the digits 4 to 9 are its own, so that no quick slot is used by mistake")
	check(not rc.on_key(_key(KEY_A)), "any other key goes on")
	# the controls table says it
	eq(ControlsTable.key_text("inv_slot"), "1 2 3 4", "the Controls page names the belt's keys")
	var speeds := ""
	for grp in ControlsTable.groups(false):
		for r in grp.rows:
			if String(r.what).begins_with("Normal speed"):
				speeds = String(r.keys)
	eq(speeds, "Shift 1 2 3", "and the speeds as Shift and 1 2 3")


func test_the_windows_are_put_against_each_other_and_the_pair_stays_in_the_budget() -> void:
	if not InvApi.available():
		return
	for size in [Vector2i(1280, 720), Vector2i(1024, 640)]:
		var g := await _ui_game(size.x, size.y)
		var sim = g.sim
		var ui = g.ui
		var vp: Vector2 = g.ctx.hud.size
		check(vp.x >= float(size.x) - 1.0 and vp.y >= float(size.y) - 1.0, "the HUD has the window's size (%s)" % str(vp))
		ui.open_pack()
		await Kit.settle()
		ui._place()
		var pack_rect: Rect2 = ui.pack_win.get_global_rect() if ui.pack_win.visible else Rect2()
		check(pack_rect.size.x > 0.0, "the pack is up at %s" % str(size))
		check(InvGeom.within_budget([pack_rect], vp), "the pack alone is inside the budget at %s: %s" % [str(size), str(InvGeom.budget_of([pack_rect], vp))])
		# a container opens: the loot window is put against the pack
		var h: int = sim.houses.start_house()
		var cont: Dictionary = sim.houses.containers_of(h)[0]
		var grid := InvApi.make_grid(4, 3)
		InvApi.place(grid, "canned_food", 2, 0, 0)
		InvApi.place(grid, "medkit", 1, 1, 1)
		sim.inv.containers[String(cont.id)] = grid
		sim.inv.open_id = String(cont.id)
		sim.inv.searched[String(cont.id)] = true
		sim.inv.changed()
		ui._dirty = true
		ui._poll()
		await Kit.settle()
		ui._place()
		check(ui.loot_win.visible and ui.pack_win.visible, "the loot window and the pack are up at %s" % str(size))
		var pr: Rect2 = ui.pack_win.get_global_rect()
		var lr: Rect2 = ui.loot_win.get_global_rect()
		check(not pr.intersects(lr), "they do not cover each other (%s, %s)" % [str(pr), str(lr)])
		check(InvGeom.within_budget([pr, lr], vp), "the pair is inside the budget at %s: %s" % [str(size), str(InvGeom.budget_of([pr, lr], vp))])
		check(Rect2(Vector2.ZERO, vp).encloses(pr) and Rect2(Vector2.ZERO, vp).encloses(lr), "both are inside the window")
		# the stash replaces the container
		sim.inv.close_container()
		sim.inv.stash_open = true
		sim.inv.changed()
		ui._dirty = true
		ui._poll()
		await Kit.settle()
		ui._place()
		check(ui.stash_win.visible and ui.pack_win.visible and not ui.loot_win.visible, "the stash panel and the pack are up at %s" % str(size))
		var pr2: Rect2 = ui.pack_win.get_global_rect()
		var sr: Rect2 = ui.stash_win.get_global_rect()
		check(not pr2.intersects(sr), "they do not cover each other (%s, %s)" % [str(pr2), str(sr)])
		check(InvGeom.within_budget([pr2, sr], vp), "the pair is inside the budget at %s: %s" % [str(size), str(InvGeom.budget_of([pr2, sr], vp))])
		ui.close_all()
		_free_ui_game(g)
