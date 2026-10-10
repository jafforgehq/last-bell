## The inventory windows' one door to the rules (INV-UI): everything the windows ask of, or tell, the sim goes through here, so that the rest of the UI never names a sim file.
##
##   - THE LOGIC: the static functions of `scripts/sim/inventory.gd` (INV-CORE; 'Sim API' of docs/superpowers/specs/2026-10-09-inventory-design.md) on grids: a grid is {"w", "h", "cells":
##     [{"item", "x", "y", "rot": bool, "count"}]}, an index is a place in `cells`.
##   - THE SIM'S PART: `sim.inv` (scripts/town/inv.gd): `pack`, `open_id` (the container whose loot window is open), `grid_of(id)`, `revealed(id)`, `stash_open`, `version`, and the calls the
##     windows make (`take_item`, `move_item`, `put_back`, `drop`, `use_item`, `deposit_item`, `deposit_all`, `withdraw`, `take_all_open`, `close_container`, `close_stash`, `changed`),
##     `carried_totals()`, `store_totals()`, `bar_totals()`, `equipment()`.
## A view only: nothing here keeps state but the item table.
extends RefCounted

## The logic is loaded when first asked for, not preloaded: a tree that has the windows and not yet the rules (the two were built side by side) runs with the windows asleep, not broken.
const INVENTORY := "res://scripts/sim/inventory.gd"

static var _defs := {}
static var _lib = null


## The logic's script (its static functions are called on it); null while it is not in the tree.
static func lib():
	if _lib == null and ResourceLoader.exists(INVENTORY):
		_lib = load(INVENTORY)
	return _lib


static func available() -> bool:
	return lib() != null


## Forgets what was read (a test that changes the data).
static func reset() -> void:
	_defs = {}


# ------------------------------------------------------------------------------- the items --

## The items by id, each as {"id", "name", "w", "h", "stack", "res", "units", "use", "desc"}.
static func defs() -> Dictionary:
	if not _defs.is_empty() or not available():
		return _defs
	var out := {}
	for id in lib().item_ids():
		out[String(id)] = _norm(String(id), lib().item(String(id)))
	_defs = out
	return _defs


static func _norm(id: String, d: Dictionary) -> Dictionary:
	return {
		"id": id, "name": String(d.get("name", id.capitalize().replace("_", " "))), "w": maxi(int(d.get("w", 1)), 1), "h": maxi(int(d.get("h", 1)), 1),
		"stack": maxi(int(d.get("stack", 1)), 1), "res": String(d.get("res", "")), "units": maxi(int(d.get("units", 1)), 1), "use": String(d.get("use", "none")),
		"desc": String(d.get("desc", "")),
	}


static func item(id: String) -> Dictionary:
	var d: Dictionary = defs()
	if d.has(id):
		return d[id]
	return {"id": id, "name": id.capitalize().replace("_", " "), "w": 1, "h": 1, "stack": 1, "res": "", "units": 1, "use": "none", "desc": ""}


## The footprint of an item in cells, turned by `rot` (0 or 1, or a bool: a turn swaps the sides).
static func size_of(id: String, rot = 0) -> Vector2i:
	var d := item(id)
	return Vector2i(int(d.h), int(d.w)) if bool(rot) else Vector2i(int(d.w), int(d.h))


# ------------------------------------------------------------------------------- the logic --

static func make_grid(w: int, h: int) -> Dictionary:
	return lib().make_grid(w, h)


static func can_place(grid: Dictionary, id: String, count: int, x: int, y: int, rot = 0, ignore: int = -1) -> bool:
	return lib().can_place(grid, id, count, x, y, bool(rot), ignore)


static func place(grid: Dictionary, id: String, count: int, x: int, y: int, rot = 0) -> int:
	return lib().place(grid, id, count, x, y, bool(rot))


static func remove(grid: Dictionary, index: int) -> Dictionary:
	return lib().remove(grid, index)


## Moves a stack to a cell of a grid (the same one, or another): onto free cells the whole stack goes; onto a stack of its kind that has room it is a merge. True when anything moved.
static func move(from_grid: Dictionary, index: int, to_grid: Dictionary, x: int, y: int, rot = 0) -> bool:
	return lib().move(from_grid, index, to_grid, x, y, bool(rot))


## Splits `count` off the stack at `index` into a stack of its own: the index of the new stack, or -1.
static func split(grid: Dictionary, index: int, count: int) -> int:
	return lib().split(grid, index, count)


## Units left over.
static func auto_add(grid: Dictionary, id: String, count: int) -> int:
	return lib().auto_add(grid, id, count)


static func quick_move(from_grid: Dictionary, index: int, to_grid: Dictionary) -> bool:
	return lib().quick_move(from_grid, index, to_grid)


static func take_all(from_grid: Dictionary, to_grid: Dictionary) -> int:
	return lib().take_all(from_grid, to_grid)


static func units(grid: Dictionary, res: String) -> int:
	return lib().units(grid, res)


## The cells a grid's stacks cover and the cells it has.
static func used_cells(grid: Dictionary) -> int:
	return lib().used_cells(grid)


static func cell_count(grid: Dictionary) -> int:
	return lib().cell_count(grid)


# --------------------------------------------------------------------------- what the sim holds --

## `sim.inv` (null in a game that has none: the school yard, the demo; a staged run sets one by hand).
static func inv(sim):
	if sim == null:
		return null
	var i = sim.get("inv")
	if i == null and sim is Object and (sim as Object).has_meta("inv"):
		i = (sim as Object).get_meta("inv")
	return i


## Whether this run has the inventory: the town's, with `sim.inv` switched on.
static func active(sim) -> bool:
	var i = inv(sim)
	if i == null or sim.get("houses") == null or not available():
		return false
	return not i.has_method("active") or bool(i.active())


## The backpack grid ({} when there is none).
static func pack(sim) -> Dictionary:
	var i = inv(sim)
	var g = i.get("pack") if i != null else null
	return g if g is Dictionary and (g as Dictionary).has("cells") else {}


## A number that goes up whenever the pack, a container or the stash's numbers changed (the windows look again when it moves).
static func version(sim) -> int:
	var i = inv(sim)
	var v = i.get("version") if i != null else null
	return int(v) if v != null else 0


## The open container, as {"id", "name", "grid", "revealed", "at"}, or {} while none is open. `revealed` counts the first stacks that are shown.
static func loot(sim) -> Dictionary:
	var i = inv(sim)
	if i == null:
		return {}
	var id := String(i.get("open_id") if i.get("open_id") != null else "")
	if id == "":
		return {}
	var g: Dictionary = i.grid_of(id)
	if g.is_empty():
		return {}
	var n: int = g.cells.size()
	var rev: int = int(i.revealed(id))
	if i is Object and (i as Object).has_meta("stage_revealed"):
		rev = int((i as Object).get_meta("stage_revealed"))    # (a staged screenshot of a search half done: scripts/ui/inv_stage.gd)
	var name := id
	var at = null
	var hs = sim.get("houses")
	if hs != null and hs.has_method("container"):
		var c: Dictionary = hs.container(id)
		name = String(c.get("name", c.get("kind", id))).replace("_", " ")
		if c.has("at"):
			at = Vector2(c.at)
		elif c.has("pos"):
			at = Vector2(c.pos)
	return {"id": id, "name": name.capitalize() if name == name.to_lower() else name, "grid": g, "revealed": clampi(rev, 0, n), "at": at}


## The stash panel is open.
static func stash_open(sim) -> bool:
	var i = inv(sim)
	return i != null and bool(i.get("stash_open"))


## What she carries by store ({"ammo", "food", "water", "meds"}).
static func carried_totals(sim) -> Dictionary:
	var i = inv(sim)
	var r = i.carried_totals() if i != null and i.has_method("carried_totals") else {}
	return r if r is Dictionary else {}


## What the base stores hold ({"ammo", "food", "water", "meds", "scrap"}).
static func store_totals(sim) -> Dictionary:
	var i = inv(sim)
	var r = i.store_totals() if i != null and i.has_method("store_totals") else {}
	return r if r is Dictionary else {}


## What the top bar shows: what she carries before the claim, the stores after it.
static func bar_totals(sim) -> Dictionary:
	var i = inv(sim)
	var r = i.bar_totals() if i != null and i.has_method("bar_totals") else {}
	return r if r is Dictionary else {}


## Her hunger and thirst (PH10): {"hunger": {h, state: fed | hungry | starving, level}, "thirst": {h, state: fed | thirsty | parched, level}, "any"}; {} for a run with no pack.
static func needs(sim) -> Dictionary:
	var i = inv(sim)
	var r = i.needs() if i != null and i.has_method("needs") else {}
	return r if r is Dictionary else {}


## The gun and the swing: {"weapon": {id, name, mag, cap, reserve, reloading}, "melee": {name}}.
static func equipment(sim) -> Dictionary:
	var i = inv(sim)
	var r = i.equipment() if i != null and i.has_method("equipment") else {}
	return r if r is Dictionary else {}


# ----------------------------------------------------------------------------- the quick slots --

## How many quick slots the belt has.
const QUICK_SLOTS := 4


## The belt: the item id of each quick slot ("" for an empty one), always QUICK_SLOTS long (a run with no belt has four empty ones).
static func quick(sim) -> Array:
	var i = inv(sim)
	var q = i.get("quick") if i != null else null
	var out: Array = []
	for k in QUICK_SLOTS:
		out.append(String(q[k]) if q is Array and k < (q as Array).size() else "")
	return out


## Whether an item may go on the belt: anything that has a use (a bandage, a meal, a drink); shells and the like do not.
static func quick_ok(id: String) -> bool:
	return id != "" and defs().has(id) and String(item(id).use) != "none"


## Puts an item kind on a quick slot ("" empties it). False for a slot that is none or an item that cannot go on the belt.
static func set_quick(sim, slot: int, id: String) -> bool:
	var i = inv(sim)
	if i == null or slot < 0 or slot >= QUICK_SLOTS or (id != "" and not quick_ok(id)):
		return false
	var q = i.get("quick")
	if not (q is Array) or (q as Array).size() < QUICK_SLOTS:
		return false
	for k in QUICK_SLOTS:
		if id != "" and k != slot and String(q[k]) == id:
			q[k] = ""    # (a kind sits on one slot only: moving it empties the slot it was on)
	q[slot] = id
	i.version = int(i.version) + 1
	return true


## The first stack of an item kind in the pack: its index in `cells`, -1 when she has none.
static func first_stack(grid: Dictionary, id: String) -> int:
	if grid.is_empty():
		return -1
	for k in (grid.cells as Array).size():
		if String(grid.cells[k].item) == id:
			return k
	return -1


## How many of an item kind the pack holds (the sum of its stacks).
static func count_of(grid: Dictionary, id: String) -> int:
	var n := 0
	if grid.is_empty():
		return 0
	for c in grid.cells:
		if String(c.item) == id:
			n += int(c.count)
	return n


# ------------------------------------------------------------------------------- what is done --

## Something in the pack changed outside the sim's own calls (a move inside the pack): it tells the windows, and the rules settle what needs it.
static func changed(sim) -> void:
	var i = inv(sim)
	if i != null and i.has_method("changed"):
		i.changed()


static func close_container(sim) -> void:
	var i = inv(sim)
	if i != null and i.has_method("close_container"):
		i.close_container()


static func close_stash(sim) -> void:
	var i = inv(sim)
	if i != null and i.has_method("close_stash"):
		i.close_stash()


## A stack of the open container into the pack, wherever it fits: true when anything moved.
static func take_item(sim, id: String, index: int) -> bool:
	return bool(inv(sim).take_item(id, index))


## A stack of the open container to a cell of the pack (a drag).
static func move_item(sim, id: String, index: int, x: int, y: int, rot = 0) -> bool:
	return bool(inv(sim).move_item(id, index, x, y, bool(rot)))


## A stack of the pack into the open container, to a cell of it (a drag back).
static func put_back(sim, id: String, index: int, x: int, y: int, rot = 0) -> bool:
	return bool(inv(sim).put_back(id, index, x, y, bool(rot)))


## Everything found in the open container into the pack: the units moved.
static func take_all_open(sim) -> int:
	return int(inv(sim).take_all_open())


static func drop(sim, index: int, count: int = -1) -> bool:
	return bool(inv(sim).drop(index, count))


## Uses a stack of the pack: {"ok", "why"}.
static func use_item(sim, index: int) -> Dictionary:
	var r = inv(sim).use_item(index)
	return r if r is Dictionary else {"ok": false, "why": ""}


## One stack of the pack into the stores: the units.
static func deposit_item(sim, index: int) -> int:
	return int(inv(sim).deposit_item(index))


## The whole pack that stands for stores into the stores: {res: units}.
static func deposit_all(sim) -> Dictionary:
	var r = inv(sim).deposit_all()
	return r if r is Dictionary else {}


## Units of a store out of the stores into the pack, as items: the units moved.
static func withdraw(sim, res: String, n: int) -> int:
	return int(inv(sim).withdraw(res, n))
