## A scripted probe of the inventory windows (INV-UI): drag, rotate, split, merge, quick-move, take-all, deposit and withdraw, the keys and the closing, through the controller's own
## handlers (`grid_input` with real mouse events, `on_key` with real key events), printing PASS or FAIL for each. Run it on the staged game:
##   Godot --path . --winpx=1280x800 --os-scale=1 -- --town=1 --stage=claimed --inv=probe --frames=80 --shot=/tmp/probe.png
## (`scripts/ui/inv_stage.gd` makes the sample pack and calls `run` a few frames in.) Lines are "PROBE name: PASS|FAIL detail"; the last is "PROBE total: n passed, m failed".
extends RefCounted

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvStage := preload("res://scripts/ui/inv_stage.gd")

var ui
var sim
var inv
var passed := 0
var failed := 0


func run(controller) -> void:
	ui = controller
	sim = ui.sim
	inv = InvApi.inv(sim)
	_drag_by_events()
	_rotate()
	_merge()
	_split()
	_loot_quick_and_take_all()
	_stash()
	_keys()
	_closing()
	print("PROBE total: %d passed, %d failed" % [passed, failed])


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("PROBE %s: %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _pack() -> Dictionary:
	return InvApi.pack(sim)


func _index_of(grid: Dictionary, item: String, nth: int = 0) -> int:
	var n := 0
	for i in grid.cells.size():
		if String(grid.cells[i].item) == item:
			if n == nth:
				return i
			n += 1
	return -1


func _local_center(g, x: int, y: int, w: int = 1, h: int = 1) -> Vector2:
	return Vector2(g.PAD, g.PAD) + (Vector2(float(x), float(y)) + Vector2(float(w), float(h)) * 0.5) * g.cell


func _mouse(g, pos: Vector2, pressed: bool, double: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.double_click = double
	ui.grid_input(g, ev)


func _motion(g, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ui.grid_input(g, ev)


func _key(code: Key) -> bool:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ui.on_key(ev)


func _units(grid: Dictionary, item: String) -> int:
	var n := 0
	for c in grid.cells:
		if String(c.item) == item:
			n += int(c.count)
	return n


func _open_loot(revealed: int, searched: bool = true) -> Dictionary:
	var g := InvStage.container_grid()
	var id := InvStage.open_container(sim, g, revealed)
	if searched:
		inv.searched[id] = true
	ui._dirty = true
	ui._poll()
	return g


## A press on the first stack of shells, a move to the empty cell at (7, 3), a release: the stack is there.
func _drag_by_events() -> void:
	var g = ui.pack_win.grid_ctl
	var pk := _pack()
	var i := _index_of(pk, "shells", 0)
	var before := _units(pk, "shells")
	_mouse(g, _local_center(g, 0, 0), true)
	_motion(g, _local_center(g, 3, 2))    # (further than the drag threshold: the stack is picked up)
	var held: bool = not ui.drag.is_empty()
	_motion(g, _local_center(g, 7, 3))
	var state := String(ui.drag.target.state) if held else ""
	_mouse(g, _local_center(g, 7, 3), false)
	var c: Dictionary = pk.cells[i] if i >= 0 and i < pk.cells.size() else {}
	_check("drag: picked up by a press and a move", held, "drag held=%s" % str(held))
	_check("drag: the frame over a free cell is green", state == "free", state)
	_check("drag: dropped on the empty cell", not c.is_empty() and int(c.x) == 7 and int(c.y) == 3 and ui.drag.is_empty(), str(c))
	_check("drag: nothing lost", _units(pk, "shells") == before, "%d -> %d" % [before, _units(pk, "shells")])
	# over a stack that does not take it: red, and the drop changes nothing
	var j := _index_of(pk, "medkit", 0)
	var mc: Dictionary = pk.cells[j].duplicate()
	_mouse(g, _local_center(g, 7, 3), true)
	_motion(g, _local_center(g, 6, 3))
	_motion(g, _local_center(g, 4, 1))
	var bad := String(ui.drag.target.state) if not ui.drag.is_empty() else ""
	_mouse(g, _local_center(g, 4, 1), false)
	_check("drag: the frame over a stack is red", bad == "blocked", bad)
	_check("drag: a red drop changes nothing", pk.cells[j].x == mc.x and pk.cells[j].y == mc.y and int(pk.cells[_index_of(pk, "shells", 0)].x) == 7, "")


## R on a held bottle (1 by 2) turns it to 2 by 1; the drop puts it down turned.
func _rotate() -> void:
	var g = ui.pack_win.grid_ctl
	var pk := _pack()
	var i := _index_of(pk, "water_bottle", 0)
	var from: Vector2 = g.get_global_rect().position + g.rect_of(i).get_center()
	ui.begin_drag(g, i, from)
	var rot_before := int(ui.drag.rot)
	var eaten := _key(KEY_R)
	var rot_after := int(ui.drag.rot) if not ui.drag.is_empty() else -1
	var gp: Vector2 = g.get_global_rect().position + _local_center(g, 2, 3)    # (a free 2 by 1 place: the bottom row)
	ui.drag_move(gp)
	var state := String(ui.drag.target.state) if not ui.drag.is_empty() else ""
	ui.drop_at(gp)
	var c: Dictionary = pk.cells[i]
	_check("rotate: R while dragging turns the item", eaten and rot_before == 0 and rot_after == 1, "rot %d -> %d, key used=%s" % [rot_before, rot_after, str(eaten)])
	_check("rotate: dropped turned on a free place", state == "free" and int(c.rot) == 1 and int(c.y) == 3, "%s rot=%d at (%d,%d)" % [state, int(c.rot), int(c.x), int(c.y)])
	_check("rotate: R with nothing held is left to the reload", not _key(KEY_R), "")


## A stack of bandages dropped on another joins it (up to the stack's most), nothing lost.
func _merge() -> void:
	var g = ui.pack_win.grid_ctl
	var pk := _pack()
	var a := _index_of(pk, "bandage", 1)    # (two bandages, dropped on the three: the stack takes one more and keeps its most)
	var b := _index_of(pk, "bandage", 0)
	var total := _units(pk, "bandage")
	var cb: Dictionary = pk.cells[b]
	var ca: Dictionary = pk.cells[a]
	var gp: Vector2 = g.get_global_rect().position + _local_center(g, int(cb.x), int(cb.y))
	ui.begin_drag(g, a, g.get_global_rect().position + _local_center(g, int(ca.x), int(ca.y)))
	ui.drag_move(gp)
	var state := String(ui.drag.target.state)
	ui.drop_at(gp)
	_check("merge: a stack over a stack of its kind says merge", state == "merge", state)
	var cap := int(InvApi.item("bandage").stack)
	var biggest := 0
	for c in pk.cells:
		if String(c.item) == "bandage":
			biggest = maxi(biggest, int(c.count))
	_check("merge: nothing lost, none over the stack's most", _units(pk, "bandage") == total and biggest == cap, "units %d of %d, biggest stack %d of %d" % [_units(pk, "bandage"), total, biggest, cap])


## The menu's Split in half: two stacks, the same units.
func _split() -> void:
	var g = ui.pack_win.grid_ctl
	var pk := _pack()
	var i := _index_of(pk, "shells", 1)
	if i < 0:
		i = _index_of(pk, "shells", 0)
	var total := _units(pk, "shells")
	var stacks := 0
	for c in pk.cells:
		if String(c.item) == "shells":
			stacks += 1
	ui._open_menu(g, i, g.get_global_rect().position + g.rect_of(i).get_center())
	var labels: Array = []
	for e in ui.menu.entries:
		labels.append(String(e[1]))
	ui.menu_pick("split_half")
	var after := 0
	for c in pk.cells:
		if String(c.item) == "shells":
			after += 1
	_check("split: the menu offers split for a stack", labels.has("split_half"), str(labels))
	_check("split: one stack became two, the units are the same", after == stacks + 1 and _units(pk, "shells") == total, "stacks %d -> %d, units %d -> %d" % [stacks, after, total, _units(pk, "shells")])


## A container with all five found: a double-click moves one stack to the pack; Take all moves the rest; a container that is half found gives only what is found.
func _loot_quick_and_take_all() -> void:
	var pk := _pack()
	pk.cells.clear()
	var lg := _open_loot(5)
	var lgc = ui.loot_win.grid_ctl
	_check("loot: the window comes up with the container", ui.loot_win.visible and ui.pack_win.visible, "loot=%s pack=%s" % [str(ui.loot_win.visible), str(ui.pack_win.visible)])
	var before: int = lg.cells.size()
	_mouse(lgc, _local_center(lgc, 0, 0), true, true)    # (the second press of a double-click)
	_check("loot: a double-click moves the stack to the pack", lg.cells.size() == before - 1 and pk.cells.size() >= 1, "container %d -> %d, pack %d" % [before, lg.cells.size(), pk.cells.size()])
	# a half-done search: Take all takes what is found, not the rest
	inv.set_meta("stage_revealed", 2)
	ui._dirty = true
	ui._poll()
	var n_before: int = lg.cells.size()
	ui.take_all_pressed()
	_check("loot: Take all takes what is found, not the rest", lg.cells.size() == n_before - 2 and ui.loot_win.visible, "container %d -> %d" % [n_before, lg.cells.size()])
	inv.set_meta("stage_revealed", lg.cells.size())
	ui._dirty = true
	ui._poll()
	ui.take_all_pressed()
	ui._poll()
	var gone := InvApi.loot(sim).is_empty()
	_check("loot: Take all with all found empties it and shuts the window", lg.cells.is_empty() and gone and not ui.loot_win.visible, "left %d, loot open=%s" % [lg.cells.size(), str(not gone)])
	# a full pack: what does not fit stays
	InvStage.full_pack(pk)
	var lg2 := _open_loot(5)
	ui.take_all_pressed()
	_check("loot: Take all into a full pack leaves what does not fit", not lg2.cells.is_empty() and ui.loot_win.visible, "left %d" % lg2.cells.size())
	ui.close_loot()
	_check("loot: closing tells the rules", InvApi.loot(sim).is_empty() and not ui.loot_win.visible, "")


## At the stash: one stack onto the stores, Deposit all, withdraw 1 and all.
func _stash() -> void:
	var pk := _pack()
	InvStage.mixed_pack(pk)
	var stock: Dictionary = sim.stock
	stock["food"] = 10.0
	stock["water"] = 5.0
	inv.stash_open = true
	ui._dirty = true
	ui._poll()
	_check("stash: the panel comes up beside the pack", ui.stash_win.visible and ui.pack_win.visible, "")
	var food_before := float(stock.food)
	var i := _index_of(pk, "canned_food", 0)
	var n := int(pk.cells[i].count)
	ui.deposit_index(i)
	_check("stash: one stack deposited into the stores", is_equal_approx(float(stock.food), food_before + float(n)), "food %d -> %d (a stack of %d)" % [int(food_before), int(stock.food), n])
	var ammo_before := float(stock.ammo)
	ui.deposit_all_pressed()
	var gained := float(stock.ammo) - ammo_before
	_check("stash: Deposit all puts every store item into the stores", InvApi.units(pk, "ammo") == 0 and InvApi.units(pk, "water") == 0 and gained > 0.0, "ammo +%d" % int(gained))
	var w_before := float(stock.water)
	ui.withdraw_pressed("water", 1)
	_check("stash: Withdraw 1 water gives a bottle", int(stock.water) == int(w_before) - 1 and InvApi.units(pk, "water") == 1, "stores %d -> %d, pack %d" % [int(w_before), int(stock.water), InvApi.units(pk, "water")])
	var pack_ammo_before := InvApi.units(pk, "ammo")
	ui.withdraw_pressed("ammo", -1)
	_check("stash: Withdraw all ammo fills the pack as far as it fits", InvApi.units(pk, "ammo") > pack_ammo_before, "pack %d, stores %d" % [InvApi.units(pk, "ammo"), int(stock.ammo)])
	ui.close_stash()
	_check("stash: closing tells the rules", not InvApi.stash_open(sim) and not ui.stash_win.visible, "")


## Tab and I open and shut the pack, Esc puts away what is up, Space takes all only with a container open.
func _keys() -> void:
	ui.close_all()
	_check("keys: nothing is up", not ui.is_open(), "")
	var used := _key(KEY_TAB)
	_check("keys: Tab opens the pack", used and ui.pack_win.visible, "")
	_key(KEY_TAB)
	_check("keys: Tab again shuts it", not ui.is_open(), "")
	_key(KEY_I)
	_check("keys: I opens it", ui.pack_win.visible, "")
	_key(KEY_ESCAPE)
	_check("keys: Esc shuts it", not ui.is_open(), "")
	_check("keys: Esc with nothing up is left to the menu", not _key(KEY_ESCAPE), "")
	_check("keys: Space with no container is left to the pause", not _key(KEY_SPACE), "")
	var pk := _pack()
	pk.cells.clear()
	var lg := _open_loot(5)
	var n: int = lg.cells.size()
	var took := _key(KEY_SPACE)
	_check("keys: Space takes all with a container open", took and lg.cells.size() < n, "container %d -> %d" % [n, lg.cells.size()])
	_open_loot(5)
	_key(KEY_TAB)
	_check("keys: Tab shuts the container too", not ui.is_open() and InvApi.loot(sim).is_empty(), "")


## The rules shut the container (she walked away: `close_container`): the window goes with it, and the pack that was only there for it.
func _closing() -> void:
	ui.close_all()
	_open_loot(5)
	_check("closing: a container opens the pack beside it", ui.loot_win.visible and ui.pack_win.visible, "")
	inv.close_container()
	ui._poll()
	_check("closing: the rules shutting it shuts the window and the pack with it", not ui.loot_win.visible and not ui.pack_win.visible, "")
	ui.pack_user = true
	_open_loot(5)
	inv.close_container()
	ui._poll()
	_check("closing: a pack the player opened stays", not ui.loot_win.visible and ui.pack_win.visible, "")
	ui.close_all()
