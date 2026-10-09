## THE GRID INVENTORY (INV-CORE, docs/superpowers/specs/2026-10-09-inventory-design.md): the pure logic of Ruth's backpack, of a container's grid and of the stash's deposit and withdraw.
## Static functions on plain data, no nodes, no `sim.rng`: the same calls give the same grids. Every number is `assets/data/items.json` (read once; `set_config` puts a block aside for a test).
##
## A GRID is {"w", "h", "cells": [placement, ...]} and a PLACEMENT is {"item": id, "x", "y", "rot": bool, "count"}: the item's w by h cells (turned when `rot`) from the cell (x, y), `count` of the
## item in it (at most the item's `stack`: a placement covers its cells whatever its count). An INDEX is a place in `grid.cells`; removing a placement shifts the ones after it, so a caller that
## holds an index reads the grid again after a call that may have removed one (`remove`, `move`, `merge`, `take_all`, `quick_move`, `take_units`, `deposit_all`).
## STORES are the colony's counts ({res: float}: `sim.stock`); an item stands for `units` of its `res` and nothing else, so what goes in a grid and out of it is the same units of the same store.
extends RefCounted

const DATA_PATH := "res://assets/data/items.json"
const MAX_ROWS := 12

static var _cfg := {}
static var _read := false


## The whole data block ({} when the file is missing: no item is known, every call fails safe).
static func config() -> Dictionary:
	if not _read:
		_read = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_cfg = parsed
	return _cfg


## Puts a block aside for a test (null: read the file again).
static func set_config(c) -> void:
	if c == null:
		_read = false
		_cfg = {}
	else:
		_read = true
		_cfg = c


# ------------------------------------------------------------------------------ items --

## The data of an item ({} for an id that is none).
static func item(id: String) -> Dictionary:
	var items = config().get("items", {})
	if typeof(items) != TYPE_DICTIONARY or not (items as Dictionary).has(id) or typeof(items[id]) != TYPE_DICTIONARY:
		return {}
	return items[id]


static func item_ids() -> Array:
	var items = config().get("items", {})
	var out: Array = (items as Dictionary).keys() if typeof(items) == TYPE_DICTIONARY else []
	out.sort()
	return out


static func name_of(id: String) -> String:
	return String(item(id).get("name", id))


## The cells an item covers (w, h), turned when `rot`.
static func size_of(id: String, rot: bool = false) -> Vector2i:
	var d := item(id)
	var w := maxi(1, int(d.get("w", 1)))
	var h := maxi(1, int(d.get("h", 1)))
	return Vector2i(h, w) if rot else Vector2i(w, h)


## The most items in one placement.
static func stack_of(id: String) -> int:
	return maxi(1, int(item(id).get("stack", 1)))


## The store units one item stands for.
static func units_of(id: String) -> int:
	return maxi(0, int(item(id).get("units", 0)))


## The store resource an item stands for ("" for none).
static func res_of(id: String) -> String:
	return String(item(id).get("res", ""))


## The store units of a placement.
static func placement_units(p: Dictionary) -> int:
	return int(p.get("count", 0)) * units_of(String(p.get("item", "")))


# ------------------------------------------------------------------------------ grids --

static func make_grid(w: int, h: int) -> Dictionary:
	return {"w": maxi(1, w), "h": maxi(1, h), "cells": []}


## The backpack's grid, from the data (8 by 4).
static func make_pack() -> Dictionary:
	var pk = config().get("pack", {})
	if typeof(pk) != TYPE_DICTIONARY:
		return make_grid(8, 4)
	return make_grid(int((pk as Dictionary).get("w", 8)), int((pk as Dictionary).get("h", 4)))


static func cell_count(grid: Dictionary) -> int:
	return int(grid.w) * int(grid.h)


## The cells a grid's placements cover.
static func used_cells(grid: Dictionary) -> int:
	var n := 0
	for p in grid.cells:
		var s := size_of(String(p.item), bool(p.rot))
		n += s.x * s.y
	return n


static func free_cells(grid: Dictionary) -> int:
	return cell_count(grid) - used_cells(grid)


static func is_empty(grid: Dictionary) -> bool:
	return (grid.cells as Array).is_empty()


## The grid's cells as a mask (1: covered), with the placement `ignore` left out.
static func _mask(grid: Dictionary, ignore: int = -1) -> PackedByteArray:
	var w := int(grid.w)
	var m := PackedByteArray()
	m.resize(w * int(grid.h))
	for i in (grid.cells as Array).size():
		if i == ignore:
			continue
		var p: Dictionary = grid.cells[i]
		var s := size_of(String(p.item), bool(p.rot))
		for yy in s.y:
			for xx in s.x:
				var cx: int = int(p.x) + xx
				var cy: int = int(p.y) + yy
				if cx >= 0 and cy >= 0 and cx < w and cy < int(grid.h):
					m[cy * w + cx] = 1
	return m


static func _fits(grid: Dictionary, mask: PackedByteArray, s: Vector2i, x: int, y: int) -> bool:
	var w := int(grid.w)
	if x < 0 or y < 0 or x + s.x > w or y + s.y > int(grid.h):
		return false
	for yy in s.y:
		for xx in s.x:
			if mask[(y + yy) * w + x + xx] != 0:
				return false
	return true


## The index of the placement that covers the cell (x, y), -1 for none.
static func placement_at(grid: Dictionary, x: int, y: int) -> int:
	for i in (grid.cells as Array).size():
		var p: Dictionary = grid.cells[i]
		var s := size_of(String(p.item), bool(p.rot))
		if x >= int(p.x) and y >= int(p.y) and x < int(p.x) + s.x and y < int(p.y) + s.y:
			return i
	return -1


## Whether `count` of the item can be put down with its corner at (x, y), turned or not: the item is known, the count is from 1 to its stack, every cell is in the grid and free (the placement
## `ignore` does not count as in the way: a move inside one grid).
static func can_place(grid: Dictionary, item_id: String, count: int, x: int, y: int, rot: bool = false, ignore: int = -1) -> bool:
	if item(item_id).is_empty() or count < 1 or count > stack_of(item_id):
		return false
	return _fits(grid, _mask(grid, ignore), size_of(item_id, rot), x, y)


## Puts a new placement down; the index of it, -1 when it does not fit (see `can_place`).
static func place(grid: Dictionary, item_id: String, count: int, x: int, y: int, rot: bool = false) -> int:
	if not can_place(grid, item_id, count, x, y, rot):
		return -1
	(grid.cells as Array).append({"item": item_id, "x": x, "y": y, "rot": rot, "count": count})
	return (grid.cells as Array).size() - 1


## Takes a placement out of the grid and gives it back ({} for an index that is none).
static func remove(grid: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= (grid.cells as Array).size():
		return {}
	var p: Dictionary = grid.cells[index]
	(grid.cells as Array).remove_at(index)
	return p


## The first place a placement of `count` of the item fits in a grid, turned if need be: {"x", "y", "rot"}, {} for none. `mask` is the grid's `_mask`.
static func _find_spot(grid: Dictionary, mask: PackedByteArray, item_id: String) -> Dictionary:
	var rots: Array = [false]
	var s0 := size_of(item_id, false)
	if s0.x != s0.y:
		rots.append(true)
	for rot in rots:
		var s := size_of(item_id, rot)
		for y in range(0, int(grid.h) - s.y + 1):
			for x in range(0, int(grid.w) - s.x + 1):
				if _fits(grid, mask, s, x, y):
					return {"x": x, "y": y, "rot": rot}
	return {}


## Moves a placement into another grid (or inside the same one) with its corner at (x, y), turned or not. Onto a placement of the same item that has room it is a MERGE (as many as fit move, the
## rest stay where they were); onto free cells the whole placement goes; else nothing. True when anything moved.
static func move(from_grid: Dictionary, index: int, to_grid: Dictionary, x: int, y: int, rot: bool = false) -> bool:
	if index < 0 or index >= (from_grid.cells as Array).size():
		return false
	var p: Dictionary = from_grid.cells[index]
	var id := String(p.item)
	var same := is_same(from_grid, to_grid)
	var at := placement_at(to_grid, x, y)
	if at >= 0 and not (same and at == index):
		var q: Dictionary = to_grid.cells[at]
		if String(q.item) == id and int(q.count) < stack_of(id):
			var n := mini(int(p.count), stack_of(id) - int(q.count))
			q.count = int(q.count) + n
			p.count = int(p.count) - n
			if int(p.count) <= 0:
				(from_grid.cells as Array).remove_at(index)
			return n > 0
		return false
	if same:
		if not can_place(to_grid, id, int(p.count), x, y, rot, index):
			return false
		p.x = x
		p.y = y
		p.rot = rot
		return true
	if not can_place(to_grid, id, int(p.count), x, y, rot):
		return false
	(to_grid.cells as Array).append({"item": id, "x": x, "y": y, "rot": rot, "count": int(p.count)})
	(from_grid.cells as Array).remove_at(index)
	return true


## Splits `count` of a placement off into a placement of its own at the first free place of the same grid; the new index, -1 when the count is not from 1 to one less than the stack held or
## there is no room.
static func split(grid: Dictionary, index: int, count: int) -> int:
	if index < 0 or index >= (grid.cells as Array).size():
		return -1
	var p: Dictionary = grid.cells[index]
	if count < 1 or count >= int(p.count):
		return -1
	var spot := _find_spot(grid, _mask(grid), String(p.item))
	if spot.is_empty():
		return -1
	p.count = int(p.count) - count
	(grid.cells as Array).append({"item": String(p.item), "x": int(spot.x), "y": int(spot.y), "rot": bool(spot.rot), "count": count})
	return (grid.cells as Array).size() - 1


## Pours the placement `from_index` into the placement `to_index` of the same item (as many as its stack takes); the number moved. A placement that is empty is removed: the indexes after it shift.
static func merge(grid: Dictionary, from_index: int, to_index: int) -> int:
	var n_cells := (grid.cells as Array).size()
	if from_index == to_index or from_index < 0 or to_index < 0 or from_index >= n_cells or to_index >= n_cells:
		return 0
	var p: Dictionary = grid.cells[from_index]
	var q: Dictionary = grid.cells[to_index]
	if String(p.item) != String(q.item):
		return 0
	var n := mini(int(p.count), stack_of(String(q.item)) - int(q.count))
	if n <= 0:
		return 0
	q.count = int(q.count) + n
	p.count = int(p.count) - n
	if int(p.count) <= 0:
		(grid.cells as Array).remove_at(from_index)
	return n


## Adds `count` of an item: into the stacks of it that have room first, then into new placements at the first free places (turned when that is the only way). The items left over (0: all went in).
static func auto_add(grid: Dictionary, item_id: String, count: int) -> int:
	if item(item_id).is_empty() or count <= 0:
		return maxi(count, 0)
	var left := count
	var cap := stack_of(item_id)
	for p in grid.cells:
		if left <= 0:
			break
		if String(p.item) == item_id and int(p.count) < cap:
			var n := mini(left, cap - int(p.count))
			p.count = int(p.count) + n
			left -= n
	while left > 0:
		var spot := _find_spot(grid, _mask(grid), item_id)
		if spot.is_empty():
			break
		var n2 := mini(left, cap)
		(grid.cells as Array).append({"item": item_id, "x": int(spot.x), "y": int(spot.y), "rot": bool(spot.rot), "count": n2})
		left -= n2
	return left


## How many of an item `auto_add` would take (the grid is not changed).
static func room_for(grid: Dictionary, item_id: String, count: int) -> int:
	return count - auto_add(from_dict(to_dict(grid)), item_id, count)


## Moves a placement into another grid wherever it fits (`auto_add`). True when anything moved; what did not fit stays in the placement.
static func quick_move(from_grid: Dictionary, index: int, to_grid: Dictionary) -> bool:
	if index < 0 or index >= (from_grid.cells as Array).size():
		return false
	var p: Dictionary = from_grid.cells[index]
	var left := auto_add(to_grid, String(p.item), int(p.count))
	var moved: int = int(p.count) - left
	if left <= 0:
		(from_grid.cells as Array).remove_at(index)
	else:
		p.count = left
	return moved > 0


## Moves everything that fits from one grid to another, in order; the number of items moved (the sum of the counts).
static func take_all(from_grid: Dictionary, to_grid: Dictionary) -> int:
	var moved := 0
	var i := 0
	while i < (from_grid.cells as Array).size():
		var p: Dictionary = from_grid.cells[i]
		var before: int = int(p.count)
		var left := auto_add(to_grid, String(p.item), before)
		moved += before - left
		if left <= 0:
			(from_grid.cells as Array).remove_at(i)
		else:
			p.count = left
			i += 1
	return moved


# ------------------------------------------------------------------------------ stores --

## The store units of a resource that a grid holds.
static func units(grid: Dictionary, res: String) -> int:
	var n := 0
	for p in grid.cells:
		if res_of(String(p.item)) == res:
			n += placement_units(p)
	return n


## Takes up to `n` units of a resource out of a grid: the smallest items first (so that a number of units is met exactly when it can be), and with `allow_over` a bigger item is broken into for the
## rest (a ration pack for one meal: more than `n` goes out). The units taken.
static func take_units(grid: Dictionary, res: String, n: int, allow_over: bool = false) -> int:
	var taken := 0
	if n <= 0:
		return 0
	var order: Array = []
	for i in (grid.cells as Array).size():
		if res_of(String(grid.cells[i].item)) == res:
			order.append(i)
	order.sort_custom(func(a, b):
		var ua := units_of(String(grid.cells[a].item))
		var ub := units_of(String(grid.cells[b].item))
		return ua < ub or (ua == ub and a < b))
	for i in order:
		var p: Dictionary = grid.cells[i]
		var u := units_of(String(p.item))
		if u <= 0 or taken >= n:
			continue
		var k := mini(int(p.count), (n - taken) / u)
		p.count = int(p.count) - k
		taken += k * u
	if allow_over:
		# (the rest from whole items of a bigger kind, one at a time)
		for i in order:
			var p2: Dictionary = grid.cells[i]
			var u2 := units_of(String(p2.item))
			while u2 > 0 and int(p2.count) > 0 and taken < n:
				p2.count = int(p2.count) - 1
				taken += u2
	var gone: Array = []
	for idx in order:
		if int(grid.cells[idx].count) <= 0:
			gone.append(idx)
	gone.sort()
	for j in range(gone.size() - 1, -1, -1):
		(grid.cells as Array).remove_at(int(gone[j]))
	return taken


## Puts everything in a grid that stands for a resource into the stores; {res: units put in}. What stands for nothing stays.
static func deposit_all(grid: Dictionary, stores: Dictionary) -> Dictionary:
	var out := {}
	var i := 0
	while i < (grid.cells as Array).size():
		var p: Dictionary = grid.cells[i]
		var res := res_of(String(p.item))
		if res == "" or not stores.has(res):
			i += 1
			continue
		var u := placement_units(p)
		stores[res] = float(stores[res]) + float(u)
		out[res] = int(out.get(res, 0)) + u
		(grid.cells as Array).remove_at(i)
	return out


## Takes `n` units of a resource out of the stores and puts them in the grid as items (`withdraw` in the data: the biggest kind first, the plain unit item for the rest); the units that went into
## the grid. What did not fit stays in the stores.
static func withdraw(stores: Dictionary, grid: Dictionary, res: String, n: int) -> int:
	var want := mini(n, floori(float(stores.get(res, 0.0))))
	if want <= 0:
		return 0
	var moved := add_units(grid, res, want)
	stores[res] = float(stores[res]) - float(moved)
	return moved


## Adds store units of a resource to a grid as items (the kinds of `withdraw` in the data, the biggest first, for the rest the next): the units that went in (what did not fit is not added).
static func add_units(grid: Dictionary, res: String, n: int) -> int:
	if n <= 0:
		return 0
	var kinds = config().get("withdraw", {}).get(res, [])
	if typeof(kinds) != TYPE_ARRAY or (kinds as Array).is_empty():
		var u1 = config().get("unit_items", {}).get(res, "")
		kinds = [u1] if String(u1) != "" else []
	var moved := 0
	var rest := n
	for id in kinds:
		var u := units_of(String(id))
		if u <= 0:
			continue
		var k := rest / u
		if k <= 0:
			continue
		var put := k - auto_add(grid, String(id), k)
		moved += put * u
		rest -= put * u
	return moved


# ------------------------------------------------------------------------------ saves --

static func to_dict(grid: Dictionary) -> Dictionary:
	var cells: Array = []
	for p in grid.cells:
		cells.append({"item": String(p.item), "x": int(p.x), "y": int(p.y), "rot": bool(p.rot), "count": int(p.count)})
	return {"w": int(grid.w), "h": int(grid.h), "cells": cells}


## A grid from saved data; a placement that is none (an item the data no longer has, outside the grid, on another) is dropped.
static func from_dict(d: Dictionary) -> Dictionary:
	var grid := make_grid(int(d.get("w", 1)), int(d.get("h", 1)))
	var cells = d.get("cells", [])
	if typeof(cells) != TYPE_ARRAY:
		return grid
	for c in cells:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var rot = c.get("rot", false)
		var r: bool = bool(rot) if typeof(rot) == TYPE_BOOL else int(rot) != 0
		var id := String(c.get("item", ""))
		var count := clampi(int(c.get("count", 1)), 1, stack_of(id))
		place(grid, id, count, int(c.get("x", 0)), int(c.get("y", 0)), r)
	return grid


# ------------------------------------------------------------------------- containers --

## The grid of a container of this kind (w, h) from the data.
static func container_size(kind: String) -> Vector2i:
	var all = config().get("containers", {})
	var d = (all as Dictionary).get(kind, (all as Dictionary).get("default", {})) if typeof(all) == TYPE_DICTIONARY else {}
	if typeof(d) != TYPE_DICTIONARY:
		return Vector2i(4, 3)
	return Vector2i(maxi(1, int((d as Dictionary).get("w", 4))), maxi(1, int((d as Dictionary).get("h", 3))))


## The items a container's loot units are, as [{"item", "count"}] (the biggest first): for each resource the data's `convert` list is tried in order (a chance each, rolled from `key`) while at
## least the item's units are left, and the plain unit item takes the rest, so the units are exactly the loot's. Scrap and any resource with no unit item are not items: they are not in the list.
## Pure: the same loot and key give the same items.
static func items_for_loot(loot: Dictionary, key: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(key) + 977
	var out: Array = []
	var cfg := config()
	var conv = cfg.get("convert", {})
	var unit_items = cfg.get("unit_items", {})
	for res in ["ammo", "food", "water", "meds"]:
		var n := int(floor(float(loot.get(res, 0.0))))
		if n <= 0:
			continue
		var rest := n
		var list = (conv as Dictionary).get(res, []) if typeof(conv) == TYPE_DICTIONARY else []
		for e in list:
			var id := String(e[0])
			var u := units_of(id)
			if u <= 1:
				continue
			while rest >= u and rng.randf() < float(e[1]):
				out.append({"item": id, "count": 1})
				rest -= u
		var plain := String((unit_items as Dictionary).get(res, "")) if typeof(unit_items) == TYPE_DICTIONARY else ""
		if rest > 0 and plain != "":
			var cap := stack_of(plain)
			while rest > 0:
				var k := mini(rest, cap)
				out.append({"item": plain, "count": k})
				rest -= k
	out.sort_custom(func(a, b):
		var sa := size_of(String(a.item))
		var sb := size_of(String(b.item))
		return sa.x * sa.y > sb.x * sb.y)
	return out


## The loot units of a loot dictionary that are NOT items (scrap): they go straight to the stores.
static func loose_units(loot: Dictionary) -> Dictionary:
	var out := {}
	var unit_items = config().get("unit_items", {})
	for k in loot:
		var n := int(floor(float(loot[k])))
		if n > 0 and not (unit_items as Dictionary).has(String(k)):
			out[String(k)] = n
	return out


## A container's grid with its loot in it: sized by its kind (`containers` in the data), the items of `items_for_loot` placed first-fit; a grid whose items do not all fit grows by rows.
## `grown` in the grid says how many rows it had to add (0 in every town the generator makes: a test holds it to that).
static func make_container(kind: String, loot: Dictionary, key: int) -> Dictionary:
	var sz := container_size(kind)
	var grid := make_grid(sz.x, sz.y)
	grid["grown"] = 0
	for e in items_for_loot(loot, key):
		var left := auto_add(grid, String(e.item), int(e.count))
		while left > 0 and int(grid.h) < MAX_ROWS:
			grid.h = int(grid.h) + 1
			grid["grown"] = int(grid.grown) + 1
			left = auto_add(grid, String(e.item), left)
	return grid
