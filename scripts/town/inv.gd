## `sim.inv`: RUTH'S PACK IN THE TOWN (INV-CORE, docs/superpowers/specs/2026-10-09-inventory-design.md). The sim part that holds the backpack (a grid: scripts/sim/inventory.gd), the grids of the containers
## she has opened, the piles on the ground, the stash panel's state, and the few rules that join them to the rest of the rules: the reload, the bandage and the meals draw from the pack, a search
## puts the container's items where she can take them, the stash turns the pack into stores and the stores into the pack. Everything is gated by `active()`: a run that is not a One House run (the school,
## the demo, the sim with no avatar, a test's bare town game) never turns it on and every rule answers as it did.
##
## THE UNITS. The stores stay counts (`sim.stock`: ammo, food, water, meds, scrap) and the crew and the builders use only them. An item stands for `units` of its resource (items.json), so what she
## carries to the stash and what she takes out of it is the same units. Scrap is not an item: it goes straight to the stores wherever it is found. A shot of the shotgun costs 0.34 of a unit of ammo
## (sim.gd SHELL_COST) and a bandage is one unit of meds (medical.gd BANDAGE_MEDS): a whole unit comes out of the pack at a reload (or a bandage) and the fraction left over is a CREDIT (`credit`), paid
## ahead and used up before the pack is asked again, so the economy the lab was tuned on is the same.
##
## THE WINDOWS (scripts/ui/inventory_*.gd read this and call it):
##   pack, ground, containers (id -> grid), open_id (the container whose loot window is open), stash_open (the stash panel is open), auto_take (a hand that takes everything at once: the lab's bot).
##   grid_of(id), revealed(id), items_left(id), open_container(id), close_container(), take_item(id, index), take_all_open(), move_item(id, index, x, y, rot), put_back(id, index, x, y, rot) ,
##   drop(index, count), pick_up(pile), use_item(index), deposit_all(), withdraw(res, n), carried_totals(), store_totals(), bar_totals(), equipment(), changed().
## Events told: loot_open {container}, loot_close {container}, picked {item, count, res, units, from}, pack_full {item, count, at}, dropped {item, count, at}, stash_open, deposit {units},
## withdraw {res, units}, ate {item, res, kind} (food or drink used from the pack), inv_toast {text, level} (the first hungry or thirsty), and the search's own `searched` (scripts/town/search.gd).
##
## HER NEEDS (PH10, the owner's step 2 after the pack: food and water). Ruth is a person of the colony and has her own hunger and thirst clocks (`p.hunger_h`, `p.thirst_h`: scripts/sim/supplies.gd has the
## constants and what the clocks cost: weaker from 18 and 14 hours without a meal or a drink, health lost from 36 and 24). What this part adds, in the One House with a pack only:
##   - the stores do not follow her out of the base: at the day's three meals (07:00, 13:00, 19:00) the table is served only to the people at the base (the crew: as always) and Ruth, when she is at the
##     base, takes her share from the stores like them (a meal that comes up while she is out is OWED: `owed_meal`, and the base serves it the moment she walks back in);
##   - out in the town she eats and drinks from her pack: `use_item` on an item whose use is eat or drink (the belt's keys 1 to 4, right-click Use, a double click) takes ONE store unit of it (a ration pack
##     or a jug is broken: the rest goes back as tins and bottles) and starts the clock again, as a served meal does; not before she is hungry or thirsty enough (items.json `needs`);
##   - the first time she is hungry and the first time she is thirsty a toast says which key (`told`), and what she went without since the last morning card is kept for it (`went`, `take_went`).
extends RefCounted

const Inventory := preload("res://scripts/sim/inventory.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")

const PILE_REACH := 1.3
const STASH_CLOSE := 3.0
## The pack counts as full for the base-entry reminder with this few cells free.
const FULL_CELLS := 1
const RES := ["ammo", "food", "water", "meds", "parts", "fuel"]    # (parts and fuel only ever come from the prison game)

var sim
var enabled := true
## Whether this is a One House run with a pack (set by `begin` and by a load of a save that had one).
var on := false
var pack: Dictionary = {}
## Piles on the ground: [{"item", "count", "x", "y"}].
var ground: Array = []
## Containers she has opened: id -> grid (made from the container's loot the first time it is wanted).
var containers := {}
## Containers whose search ran its course (their scrap has gone to the stores): id -> true.
var searched := {}
var open_id := ""
var stash_open := false
## The four quick slots on her belt (INV2): the id of the item each one uses ("" for an empty one). A slot names a KIND of item, not a stack: a key or a click uses the first stack of it in the pack
## (`use_item`), the stack may move, split or merge, and the slot follows. Saved with the run; nothing in the rules reads it.
var quick: Array = ["", "", "", ""]
var auto_take := false
## NEEDS: a meal hour came up while she was out of the base (the base serves it the moment she is home), the first hungry and thirsty toasts already told, and what she went without since the last
## morning card (`take_went`).
var owed_meal := false
var told := {"hungry": false, "thirsty": false}
var went := {"hungry": false, "thirsty": false, "starving": false, "parched": false}
## What the last automatic take of each container moved: id -> {res: units} (scrap too): the room search's chip reads it.
var last_taken := {}
var credit := {}
var stats := {}
## Grids made from a container's loot that nobody has opened (a cache for the windows' questions; never saved, never changed).
var _peeked := {}
var _full := false
var _was_home := false


func setup(s) -> void:
	sim = s
	start()


func start() -> void:
	on = false
	pack = Inventory.make_pack()
	ground = []
	containers = {}
	_peeked = {}
	searched = {}
	open_id = ""
	stash_open = false
	quick = ["", "", "", ""]
	last_taken = {}
	credit = {"ammo": 0.0, "food": 0.0, "water": 0.0, "meds": 0.0}
	stats = {"deposits": 0, "deposited": {}, "full": 0, "dropped": 0, "picked": {}, "peak_cells": 0, "ate": 0, "drank": 0}
	owed_meal = false
	told = {"hungry": false, "thirsty": false}
	went = {"hungry": false, "thirsty": false, "starving": false, "parched": false}
	_full = false
	_was_home = false


## A One House run begins with this pack ({item id: count}: the data's `start.pack`).
func begin(start_pack: Dictionary) -> void:
	start()
	on = true
	for id in start_pack:
		Inventory.auto_add(pack, String(id), int(start_pack[id]))
	var slot := 0
	for id in ["bandage", "canned_food", "water_bottle"]:    # (the belt starts with what she carries to heal and to live on)
		if int(start_pack.get(id, 0)) > 0:
			quick[slot] = id
			slot += 1


func active() -> bool:
	return on and enabled and sim != null and sim.is_one_house()


func _lead():
	if sim == null or String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## The person who carries the pack (Ruth), or null.
func lead():
	return _lead()


func _cfg(key: String, fallback):
	return Inventory.config().get(key, fallback)


# ------------------------------------------------------------------------------ totals --

## What she carries, by resource: {ammo, food, water, meds} in store units (the top bar before the claim, the pack chip after).
func carried_totals() -> Dictionary:
	var out := {}
	for r in RES:
		out[r] = Inventory.units(pack, r)
	out["scrap"] = 0
	return out


## What the base's stores hold: {ammo, food, water, meds, scrap}, whole numbers.
func store_totals() -> Dictionary:
	var out := {}
	for r in RES + ["scrap"]:
		out[r] = floori(float(sim.stock.get(r, 0.0)))
	return out


## What the top bar shows: what she carries before the claim, the base's stores after it.
func bar_totals() -> Dictionary:
	var base = sim.get("base")
	return store_totals() if base != null and bool(base.claimed) else carried_totals()


## The rounds in the pack (the `40` of `3 / 40`).
func reserve_rounds() -> int:
	return Inventory.units(pack, "ammo")


## The gun and the swing for the equipment slots: {"weapon": {id, name, mag, cap, reserve, reloading}, "melee": {name}}.
func equipment() -> Dictionary:
	var p = _lead()
	if p == null:
		return {"weapon": {}, "melee": {"name": "Swing"}}
	var gun: Dictionary = p.gun
	return {
		"weapon": {"id": String(p.weapon), "name": String(gun.get("name", p.weapon)), "mag": int(p.mag), "cap": int(gun.get("mag", 0)), "reserve": reserve_rounds(), "reloading": float(p.reloading)},
		"melee": {"name": "Swing"},
	}


## Everything the HUD wants to know that changed (a counter that goes up when the pack, the stores' view or a container did).
var version := 0


func changed() -> void:
	version += 1
	if open_id != "":
		_settle(open_id)
	stats.peak_cells = maxi(int(stats.peak_cells), Inventory.used_cells(pack))


# --------------------------------------------------------------------------- the credit --

## Takes `amount` store units of a resource out of the pack as a number that may be a fraction: the credit first, then whole units (a bigger item is broken into when it has to be), the rest of
## them credited. The amount given (less than `amount` when the pack ran dry).
func take_float(res: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var have := float(credit.get(res, 0.0))
	if have + 1.0e-9 < amount:
		var need := int(ceil(amount - have - 1.0e-9))
		have += float(Inventory.take_units(pack, res, need, true))
	var give := minf(amount, have)
	credit[res] = have - give
	if give > 0.0:
		version += 1
	return give


## How many shots the pack and the credit can load (at the gun's cost).
func shots_available(p) -> int:
	var cost := maxf(float(sim.shot_cost(p)), 0.001)
	return int(floor((float(Inventory.units(pack, "ammo")) + float(credit.get("ammo", 0.0)) + 1.0e-6) / cost))


## The reload: up to `want` shots into the magazine, paid from the pack. The shots loaded.
func load_shots(p, want: int) -> int:
	var shots := mini(want, shots_available(p))
	if shots <= 0:
		return 0
	take_float("ammo", float(shots) * float(sim.shot_cost(p)))
	return shots


## Medicine she can use where she stands: the pack's, and the base's stores' when she is at the base.
func meds_available(p) -> float:
	var n := float(Inventory.units(pack, "meds")) + float(credit.get("meds", 0.0))
	var base = sim.get("base")
	if base != null and bool(base.claimed) and p != null and base.at_base(p):
		n += float(sim.stock.get("meds", 0.0))
	return n


## Puts `amount` of medicine into the stores out of the pack (the pack first, then the stores are what is used: medical.gd takes it from there), so that her own bandage and cure draw from the pack
## before the base. Returns what was moved.
func stage_meds(amount: float) -> float:
	var got := take_float("meds", amount)
	if got > 0.0:
		sim.stock["meds"] = float(sim.stock.get("meds", 0.0)) + got
	return got


## A meal for her (the supplies call it when the stores cannot give her a share): the units of a resource from the pack, a fraction too. What was given.
func eat(res: String, share: float) -> float:
	return take_float(res, share)


# ------------------------------------------------------------------------------ adding --

## Puts `count` of an item in the pack; what does not fit lies on the ground at her feet with a note. Returns the count that went into the pack.
func give(item_id: String, count: int, from: String = "") -> int:
	if count <= 0 or Inventory.item(item_id).is_empty():
		return 0
	var left := Inventory.auto_add(pack, item_id, count)
	var put := count - left
	if put > 0:
		_picked(item_id, put, from)
	if left > 0:
		_overflow(item_id, left)
	version += 1
	return put


## The same for store units of a resource (a reward, an ammo box): made into items the way a withdrawal is.
func give_units(res: String, n: int, from: String = "") -> int:
	if n <= 0:
		return 0
	var put := Inventory.add_units(pack, res, n)
	if put > 0:
		var ids = _cfg("withdraw", {}).get(res, [])
		_picked(String(ids[0]) if (ids is Array and not (ids as Array).is_empty()) else res, put, from, res, put)
	if put < n:
		# (the rest lies at her feet as the plain unit item)
		var plain := String(_cfg("unit_items", {}).get(res, ""))
		if plain != "":
			_overflow(plain, n - put)
	version += 1
	return put


func _picked(item_id: String, count: int, from: String, res_override: String = "", units_override: int = -1) -> void:
	var res := res_override if res_override != "" else Inventory.res_of(item_id)
	var u := units_override if units_override >= 0 else count * Inventory.units_of(item_id)
	if res != "":
		stats.picked[res] = int(stats.picked.get(res, 0)) + u
	stats.peak_cells = maxi(int(stats.peak_cells), Inventory.used_cells(pack))
	sim.events.append({"type": "picked", "item": item_id, "count": count, "res": res, "units": u, "from": from})


## An item that has no room in the pack: a pile at her feet (it joins a pile of the same item that lies close), a note and an event.
func _overflow(item_id: String, count: int) -> void:
	var p = _lead()
	var at := Vector2(p.x, p.y) if p != null else Vector2.ZERO
	var reach := float(_cfg("drop_reach", 0.8))
	for pile in ground:
		if String(pile.item) == item_id and Vector2(float(pile.x), float(pile.y)).distance_to(at) <= reach:
			pile.count = int(pile.count) + count
			count = 0
			break
	if count > 0:
		ground.append({"item": item_id, "count": count, "x": at.x, "y": at.y})
	if not _full:
		stats.full = int(stats.full) + 1
	_full = true
	stats.dropped = int(stats.dropped) + maxi(count, 1)
	sim.events.append({"type": "pack_full", "item": item_id, "count": count, "at": at})
	sim.alert("pack-full", "warn", "Your pack is full", "Left on the ground: %s" % Inventory.name_of(item_id).to_lower(), at, 6.0)


# ----------------------------------------------------------------------- the containers --

func _town_seed() -> int:
	var t = sim.get("town_data")
	return int(t.get("seed", 0)) if typeof(t) == TYPE_DICTIONARY else 0


## The grid a container has (its state if it has one, else the grid its loot makes, which is not kept): {} for an id that is none.
func _peek(id: String) -> Dictionary:
	if containers.has(id):
		return containers[id]
	if _peeked.has(id):
		return _peeked[id]
	var hs = sim.get("houses")
	var cont: Dictionary = hs.container(id) if hs != null else {}
	if cont.is_empty():
		return {}
	var loot = cont.get("loot", {})
	var g: Dictionary
	if searched.has(id):
		# (searched and no grid kept: the crew emptied it; nothing is made again)
		var sz := Inventory.container_size(String(cont.get("kind", "default")))
		g = Inventory.make_grid(sz.x, sz.y)
	else:
		g = Inventory.make_container(String(cont.get("kind", "default")), loot if typeof(loot) == TYPE_DICTIONARY else {}, _town_seed() * 31 + id.hash())
	_peeked[id] = g
	return g


## The grid of a container, kept from now on (made from its loot the first time): {} for an id that is none. This is the one the windows change.
func grid_of(id: String) -> Dictionary:
	if containers.has(id):
		return containers[id]
	var g := _peek(id)
	if not g.is_empty():
		containers[id] = g
		_peeked.erase(id)
	return g


## How many placements a container still holds (0 for one a crew member emptied).
func items_left(id: String) -> int:
	if containers.has(id):
		return (containers[id].cells as Array).size()
	var search = sim.get("search")
	if search != null and search.looted.has(id):
		return 0
	var g := _peek(id)
	return (g.cells as Array).size() if not g.is_empty() else 0


## The units of the resources a container still holds (items only; scrap is not in a grid).
func units_in(id: String) -> Dictionary:
	var out := {}
	var g := _peek(id)
	if g.is_empty():
		return out
	for r in RES:
		var n := Inventory.units(g, r)
		if n > 0:
			out[r] = n
	return out


## How many items of a container show in the loot window now: one more every `reveal_s` seconds of its search, all of them once it is searched.
func revealed(id: String) -> int:
	var n := items_left(id)
	var search = sim.get("search")
	var u = sim.get("uses")
	if u != null and u.in_session("container", id):
		var pr: Dictionary = u.progress()
		var step := maxf(float(_cfg("reveal_s", 0.4)), 0.05)
		return mini(n, int(floor(float(pr.t) / step)))
	if searched.has(id) or (search != null and search.looted.has(id)):
		return n
	return 0


## The loot window opens for a container (its search has begun, or she is opening what was left in it).
func open_container(id: String) -> void:
	if grid_of(id).is_empty() and not containers.has(id):
		return
	if open_id != "" and open_id != id:
		close_container()
	open_id = id
	stash_open = false
	sim.events.append({"type": "loot_open", "container": id})
	version += 1


## A search began: the window opens on the container.
func on_search_begin(id: String) -> void:
	if active():
		open_container(id)


## The window closes; a container she has searched is `looted` (what is left in it can be taken later).
func close_container() -> void:
	if open_id == "":
		return
	var id := open_id
	open_id = ""
	var search = sim.get("search")
	if search != null and searched.has(id):
		search.looted[id] = true
	else:
		# (the window shut while the search is still running: the search stops with it)
		var u = sim.get("uses")
		if u != null and u.in_session("container", id):
			u.cancel("closed")
	sim.events.append({"type": "loot_close", "container": id})
	version += 1


## A container searched by the crew (abstract): its items went to the stores, so nothing is left in it and its window, if open, closes.
func forget(id: String) -> void:
	containers.erase(id)
	_peeked.erase(id)
	searched[id] = true
	if open_id == id:
		open_id = ""
		sim.events.append({"type": "loot_close", "container": id})
	version += 1


## Settles a container after something left it: an empty one is looted, and its window closes.
func _settle(id: String) -> void:
	if not searched.has(id) or not containers.has(id):
		return
	if Inventory.is_empty(containers[id]):
		var search = sim.get("search")
		if search != null:
			search.looted[id] = true
		if open_id == id:
			close_container()


## The search of a container ran its course (search.gd): its scrap has gone to the stores already. With a hand that takes everything (`auto_take`, the room search) the items go to the pack and the
## container is looted; otherwise the window stays open for her.
func on_search_done(id: String) -> void:
	grid_of(id)    # (kept from now on: before the mark, which says a container without a grid is one the crew emptied)
	searched[id] = true
	if auto_take or _room_search_running():
		var moved := take_all_from(id)
		var search = sim.get("search")
		if search != null:
			search.looted[id] = true
		if open_id == id:
			open_id = ""
		last_taken[id] = moved
	else:
		if open_id != id:
			open_container(id)
		_settle(id)    # (a container with nothing in it is looted and its window shuts at once)


func _room_search_running() -> bool:
	var rs = sim.get("room_search")
	return rs != null and rs.has_method("running") and bool(rs.running())


## Moves everything that fits from a container to the pack; {res: units} of what moved. The rest stays.
func take_all_from(id: String) -> Dictionary:
	var out := {}
	var g := grid_of(id)
	if g.is_empty():
		return out
	var i := 0
	while i < (g.cells as Array).size():
		var p: Dictionary = g.cells[i]
		var before := int(p.count)
		var left := Inventory.auto_add(pack, String(p.item), before)
		var moved := before - left
		if moved > 0:
			var res := Inventory.res_of(String(p.item))
			if res != "":    # (a gun item of the prison game stands for no store)
				out[res] = int(out.get(res, 0)) + moved * Inventory.units_of(String(p.item))
			_picked(String(p.item), moved, id)
		if left <= 0:
			(g.cells as Array).remove_at(i)
		else:
			p.count = left
			_overflow_note(String(p.item), left)
			i += 1
	version += 1
	if not Inventory.is_empty(g) and not out.is_empty():
		_full = true
	return out


func _overflow_note(item_id: String, left: int) -> void:
	if not _full:
		stats.full = int(stats.full) + 1    # (counted once for each time the pack fills up, until the next deposit)
	_full = true
	sim.alert("pack-full", "warn", "Your pack is full", "%d %s stay in the container" % [left, Inventory.name_of(item_id).to_lower()], null, 5.0)


## The Space key / the Take all button: everything that fits from the open container.
func take_all_open() -> int:
	if open_id == "":
		return 0
	var moved := take_all_from(open_id)
	var n := 0
	for r in moved:
		n += int(moved[r])
	_settle(open_id)
	return n


## Double click: one placement of the open container to the pack wherever it fits. True when anything moved.
func take_item(id: String, index: int) -> bool:
	var g := grid_of(id)
	if g.is_empty() or index < 0 or index >= (g.cells as Array).size():
		return false
	var p: Dictionary = g.cells[index]
	var item_id := String(p.item)
	var before := int(p.count)
	var ok := Inventory.quick_move(g, index, pack)
	var left := 0
	if index < (g.cells as Array).size() and is_same((g.cells as Array)[index], p):
		left = int(p.count)
	var moved := before - left
	if moved > 0:
		_picked(item_id, moved, id)
	changed()
	return ok


## A drag from a container to a cell of the pack. True when anything moved.
func move_item(id: String, index: int, x: int, y: int, rot: bool = false) -> bool:
	var g := grid_of(id)
	if g.is_empty() or index < 0 or index >= (g.cells as Array).size():
		return false
	var p: Dictionary = g.cells[index]
	var item_id := String(p.item)
	var before := int(p.count)
	var ok := Inventory.move(g, index, pack, x, y, rot)
	var left := 0
	if index < (g.cells as Array).size() and is_same((g.cells as Array)[index], p):
		left = int(p.count)
	if ok:
		_picked(item_id, before - left, id)
	changed()
	return ok


## A drag from the pack back into the open container's grid.
func put_back(id: String, index: int, x: int, y: int, rot: bool = false) -> bool:
	var g := grid_of(id)
	if g.is_empty():
		return false
	var ok := Inventory.move(pack, index, g, x, y, rot)
	changed()
	return ok


## An item out of the pack on to the ground at her feet (`count` of it, -1 for the whole placement).
func drop(index: int, count: int = -1) -> bool:
	if index < 0 or index >= (pack.cells as Array).size():
		return false
	var p: Dictionary = pack.cells[index]
	var n := int(p.count) if count < 0 else mini(count, int(p.count))
	if n <= 0:
		return false
	var item_id := String(p.item)
	p.count = int(p.count) - n
	if int(p.count) <= 0:
		(pack.cells as Array).remove_at(index)
	var me = _lead()
	var at := Vector2(me.x, me.y) if me != null else Vector2.ZERO
	var merged := false
	for pile in ground:
		if String(pile.item) == item_id and Vector2(float(pile.x), float(pile.y)).distance_to(at) <= float(_cfg("drop_reach", 0.8)):
			pile.count = int(pile.count) + n
			merged = true
			break
	if not merged:
		ground.append({"item": item_id, "count": n, "x": at.x, "y": at.y})
	sim.events.append({"type": "dropped", "item": item_id, "count": n, "at": at})
	version += 1
	return true


## A pile on the ground into the pack (what fits). True when anything moved.
func pick_up(pile_index: int) -> bool:
	if pile_index < 0 or pile_index >= ground.size():
		return false
	var pile: Dictionary = ground[pile_index]
	var before := int(pile.count)
	var left := Inventory.auto_add(pack, String(pile.item), before)
	if before - left > 0:
		_picked(String(pile.item), before - left, "ground")
	if left <= 0:
		ground.remove_at(pile_index)
	else:
		pile.count = left
	version += 1
	return left < before


## Using an item: a bandage bandages the wound if it bleeds (the E at the wound's session); food and drink are eaten and drunk (`_use_ration`). {"ok", "why", "line"}: `line` is what to say when it worked.
func use_item(index: int) -> Dictionary:
	if index < 0 or index >= (pack.cells as Array).size():
		return {"ok": false, "why": "Nothing there"}
	var kind := String(Inventory.item(String(pack.cells[index].item)).get("use", "none"))
	var p = _lead()
	if (kind == "eat" or kind == "drink") and p != null:
		return _use_ration(index, kind)
	if kind == "bandage" and p != null:
		var u = sim.get("uses")
		if float(p.bleeding) <= 0.0:
			return {"ok": false, "why": "You are not bleeding"}
		if u != null:
			var r: Dictionary = u.use({"kind": "selfcare", "id": "bandage"})
			return {"ok": bool(r.get("ok", false)), "why": String(r.get("why", "")), "line": "Bandaging"}
	return {"ok": false, "why": "Nothing to do with it"}


# ----------------------------------------------------------------------------------- her needs --

func _needs_cfg() -> Dictionary:
	var n = _cfg("needs", {})
	return n if typeof(n) == TYPE_DICTIONARY else {}


## Whether she is at the base (the claimed house's compound): where the stores serve her.
func at_home(p) -> bool:
	var base = sim.get("base")
	return base != null and bool(base.claimed) and p != null and base.at_base(p)


## A meal hour came up and she was not at the base (supplies.gd calls it): the base serves it when she is home again.
func on_meal_missed() -> void:
	owed_meal = true


## Her hunger and thirst, for the HUD and the tests: {"hunger": {"h": game hours, "state": "fed" | "hungry" | "starving", "level": 0 to 1}, "thirst": {"h", "state": "fed" | "thirsty" | "parched",
## "level"}, "any": hungry or thirsty}. `level` is how far the clock is to where it costs health (1 from there on). All fed for a run with no pack.
func needs() -> Dictionary:
	var out := {"hunger": {"h": 0.0, "state": "fed", "level": 0.0}, "thirst": {"h": 0.0, "state": "fed", "level": 0.0}, "any": false}
	var p = _lead()
	if p == null or not active():
		return out
	var hh := float(p.hunger_h)
	var th := float(p.thirst_h)
	out.hunger = {"h": hh, "state": "starving" if hh >= Supplies.STARVING_H else ("hungry" if hh >= Supplies.HUNGRY_H else "fed"), "level": clampf(hh / Supplies.STARVING_H, 0.0, 1.0)}
	out.thirst = {"h": th, "state": "parched" if th >= Supplies.PARCHED_H else ("thirsty" if th >= Supplies.THIRSTY_H else "fed"), "level": clampf(th / Supplies.PARCHED_H, 0.0, 1.0)}
	out.any = out.hunger.state != "fed" or out.thirst.state != "fed"
	return out


## The belt slot (0 to 3) that uses food (`kind` "eat") or drink ("drink") she has in the pack, -1 for none.
func slot_for(kind: String) -> int:
	for i in quick.size():
		var id := String(quick[i])
		if id != "" and String(Inventory.item(id).get("use", "none")) == kind and Inventory.count_of(pack, id) > 0:
			return i
	return -1


## Whether the pack holds anything of this use at all.
func has_use(kind: String) -> bool:
	for c in pack.cells:
		if String(Inventory.item(String(c.item)).get("use", "none")) == kind:
			return true
	return false


## The index of the first stack of the pack with this use (the smallest item first, so a tin goes before a ration pack and a bottle before a jug), -1 for none.
func first_use(kind: String) -> int:
	var best := -1
	var best_units := 1 << 30
	for i in (pack.cells as Array).size():
		var id := String(pack.cells[i].item)
		if String(Inventory.item(id).get("use", "none")) == kind and Inventory.units_of(id) < best_units:
			best = i
			best_units = Inventory.units_of(id)
	return best


## Food or drink out of the pack: ONE unit, the clock begun again. Not before she is hungry or thirsty enough (the item stays). {"ok", "why", "line"}.
func _use_ration(index: int, kind: String) -> Dictionary:
	var p = _lead()
	var food := kind == "eat"
	if p == null or p.dead or p.downed:
		return {"ok": false, "why": "Not now"}
	var cfg := _needs_cfg()
	var hours := float(p.hunger_h if food else p.thirst_h)
	var least := float(cfg.get("eat_min_h", 6.0) if food else cfg.get("drink_min_h", 5.0))
	if hours < least:
		return {"ok": false, "why": "You are not hungry yet" if food else "You are not thirsty yet"}
	var cell: Dictionary = pack.cells[index]
	var id := String(cell.item)
	var res := Inventory.res_of(id)
	var units := Inventory.units_of(id)
	var broken := units > 1
	cell.count = int(cell.count) - 1
	if int(cell.count) <= 0:
		(pack.cells as Array).remove_at(index)
	if broken:
		# (a ration pack is three tins and a jug four bottles: one is used and the rest goes back as the smaller items; the room it left is the room they need)
		var rest := units - 1
		var put := Inventory.add_units(pack, res, rest)
		if put < rest:
			var plain := String(_cfg("unit_items", {}).get(res, ""))
			if plain != "":
				_overflow(plain, rest - put)
	if food:
		p.hunger_h = 0.0
		stats["ate"] = int(stats.get("ate", 0)) + 1
	else:
		p.thirst_h = 0.0
		stats["drank"] = int(stats.get("drank", 0)) + 1
	sim.events.append({"type": "ate", "item": id, "res": res, "kind": kind})
	version += 1
	var nm := Inventory.name_of(id).to_lower()
	var line := ("Ate from the %s" % nm if broken else "Ate %s" % nm) if food else ("Drank from the %s" % nm if broken else "Drank %s" % nm)
	return {"ok": true, "why": "", "line": line}


## What she went without since the last time this was asked (the morning card asks): {"hungry", "thirsty", "starving", "parched"} as booleans, then forgotten.
func take_went() -> Dictionary:
	var out := went.duplicate()
	went = {"hungry": false, "thirsty": false, "starving": false, "parched": false}
	return out


## Every step: her clocks against the lines, for the toasts and the morning card's record.
func _needs_step(p) -> void:
	if p.dead:
		return
	var hungry: bool = float(p.hunger_h) >= Supplies.HUNGRY_H
	var thirsty: bool = float(p.thirst_h) >= Supplies.THIRSTY_H
	if hungry:
		went["hungry"] = true
		if float(p.hunger_h) >= Supplies.STARVING_H:
			went["starving"] = true
	if thirsty:
		went["thirsty"] = true
		if float(p.thirst_h) >= Supplies.PARCHED_H:
			went["parched"] = true
	if hungry and not bool(told.get("hungry", false)):
		told["hungry"] = true
		_toast_need("eat")
	if thirsty and not bool(told.get("thirsty", false)):
		told["thirsty"] = true
		_toast_need("drink")


## The one toast of the first hunger or thirst: which key, or why there is nothing to use.
func _toast_need(kind: String) -> void:
	var food := kind == "eat"
	var word := "Hungry" if food else "Thirsty"
	var slot := slot_for(kind)
	var text := ""
	if slot >= 0:
		text = "%s: press %d to %s (%s)" % [word, slot + 1, kind, Inventory.name_of(String(quick[slot])).to_lower()]
	elif has_use(kind):
		text = "%s: open the pack (Tab) and right-click %s" % [word, "food" if food else "a drink"]
	else:
		text = "%s, and nothing to %s in the pack: search the kitchens, or go home to the stores" % [word, kind]
	sim.events.append({"type": "inv_toast", "text": text, "level": "warn"})


# ----------------------------------------------------------------------------- the stash --

func _stash_pos() -> Vector2:
	var base = sim.get("base")
	if base == null or not bool(base.claimed):
		return Vector2.INF
	var st: Dictionary = base.prop("stash")
	return Vector2(st.pos) if not st.is_empty() else Vector2(base.center())


## The stash panel opens (E at the stash).
func open_stash() -> void:
	if open_id != "":
		close_container()
	stash_open = true
	sim.events.append({"type": "stash_open"})
	version += 1


func close_stash() -> void:
	if stash_open:
		stash_open = false
		version += 1


## Whether she may use the stash now: its panel is open, or she is in the base (the lab's bot, a test).
func can_stash() -> bool:
	if stash_open:
		return true
	var p = _lead()
	var base = sim.get("base")
	return p != null and base != null and bool(base.claimed) and base.at_base(p)


## Everything in the pack that stands for a resource into the stores; {res: units}. What the credit holds goes back too. {} when she cannot use the stash.
func deposit_all(force: bool = false) -> Dictionary:
	if not active() or not (force or can_stash()):
		return {}
	var got := Inventory.deposit_all(pack, sim.stock)
	for r in credit:
		if float(credit[r]) > 0.0:
			sim.stock[r] = float(sim.stock.get(r, 0.0)) + float(credit[r])
			credit[r] = 0.0
	if not got.is_empty():
		stats.deposits = int(stats.deposits) + 1
		for r in got:
			stats.deposited[r] = int(stats.deposited.get(r, 0)) + int(got[r])
		sim.events.append({"type": "deposit", "units": got})
	_full = false
	version += 1
	return got


## One item (an index of the pack) into the stores; the units. The drag onto the stores panel.
func deposit_item(index: int) -> int:
	if not active() or not can_stash() or index < 0 or index >= (pack.cells as Array).size():
		return 0
	var p: Dictionary = pack.cells[index]
	var res := Inventory.res_of(String(p.item))
	if res == "" or not sim.stock.has(res):
		return 0
	var u := Inventory.placement_units(p)
	sim.stock[res] = float(sim.stock[res]) + float(u)
	(pack.cells as Array).remove_at(index)
	stats.deposits = int(stats.deposits) + 1
	stats.deposited[res] = int(stats.deposited.get(res, 0)) + u
	sim.events.append({"type": "deposit", "units": {res: u}})
	version += 1
	return u


## Takes `n` units of a resource out of the stores into the pack; the units moved (what does not fit stays). 0 when she cannot use the stash.
func withdraw(res: String, n: int, force: bool = false) -> int:
	if not active() or not (force or can_stash()):
		return 0
	var moved := Inventory.withdraw(sim.stock, pack, res, n)
	if moved > 0:
		sim.events.append({"type": "withdraw", "res": res, "units": moved})
		version += 1
	return moved


# ---------------------------------------------------------------------------- the step --

func update(_dt: float) -> void:
	if not active():
		return
	var p = _lead()
	if p == null:
		return
	var here := Vector2(p.x, p.y)
	_needs_step(p)
	if open_id != "":
		var hs = sim.get("houses")
		var cont: Dictionary = hs.container(open_id) if hs != null else {}
		var u = sim.get("uses")
		var far: bool = cont.is_empty() or here.distance_to(Vector2(cont.get("at", cont.get("pos", here)))) > float(_cfg("close_tiles", 3.0)) + 0.5
		var cancelled: bool = not searched.has(open_id) and (u == null or not u.in_session("container", open_id))
		if far or cancelled or p.dead or p.downed:
			if cancelled and not far:
				open_id = ""    # (the search was stopped: nothing was searched, nothing to settle)
				sim.events.append({"type": "loot_close", "container": cont.get("id", "")})
				version += 1
			else:
				close_container()
	if stash_open:
		var sp := _stash_pos()
		if sp == Vector2.INF or here.distance_to(sp) > STASH_CLOSE:
			close_stash()
	# coming home with a full pack: a reminder, once for each time she walks in
	var base = sim.get("base")
	var home: bool = base != null and bool(base.claimed) and base.at_base(p)
	if home and not _was_home and (_full or Inventory.free_cells(pack) <= FULL_CELLS) and not Inventory.is_empty(pack):
		sim.alert("pack-home", "info", "Your pack is full", "Deposit it at the stash (E)", _stash_pos() if _stash_pos() != Vector2.INF else null, 8.0)
	_was_home = home


## E on a pile of the ground: "Pick up".
func candidates(p) -> Array:
	var out: Array = []
	if not active() or ground.is_empty():
		return out
	var me := Vector2(p.x, p.y)
	for i in ground.size():
		var pile: Dictionary = ground[i]
		var d := me.distance_to(Vector2(float(pile.x), float(pile.y)))
		if d <= PILE_REACH:
			out.append({"kind": "pile", "id": str(i), "label": "Pick up %d %s" % [int(pile.count), Inventory.name_of(String(pile.item)).to_lower()], "pos": Vector2(float(pile.x), float(pile.y)), "dist": d, "ok": true, "why": ""})
	return out


func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != "pile":
		return {}
	var i := int(String(c.get("id", "-1")))
	if pick_up(i):
		return {"ok": true, "line": "", "why": ""}
	return {"ok": false, "line": "", "why": "Your pack is full"}


# ------------------------------------------------------------------------ the lab's lines --

## The units still in the containers she opened and left (and on the ground): what the run left behind.
func left_behind() -> int:
	var n := 0
	for id in containers:
		for r in RES:
			n += Inventory.units(containers[id], r)
	for pile in ground:
		n += int(pile.count) * Inventory.units_of(String(pile.item))
	return n


# -------------------------------------------------------------------------------- save --

func save() -> Dictionary:
	if not on:
		return {"on": false}
	var conts := {}
	for id in containers:
		conts[String(id)] = Inventory.to_dict(containers[id])
	var piles: Array = []
	for pile in ground:
		piles.append({"item": String(pile.item), "count": int(pile.count), "x": float(pile.x), "y": float(pile.y)})
	var ids: Array = searched.keys()
	ids.sort()
	return {"on": true, "pack": Inventory.to_dict(pack), "ground": piles, "containers": conts, "searched": ids, "credit": credit.duplicate(), "stats": stats.duplicate(true), "full": _full, "quick": quick.duplicate(),
		"needs": {"owed": owed_meal, "told": told.duplicate(), "went": went.duplicate()}}


## The spec's names for the same two (`save` and `load_state` are the ones SaveGame calls).
func to_dict() -> Dictionary:
	return save()


func from_dict(d: Dictionary) -> void:
	load_state(d)


func load_state(d: Dictionary) -> void:
	start()
	on = bool(d.get("on", false))
	if not on:
		return
	var pk = d.get("pack", {})
	if typeof(pk) == TYPE_DICTIONARY and not (pk as Dictionary).is_empty():
		pack = Inventory.from_dict(pk)
	var piles = d.get("ground", [])
	if typeof(piles) == TYPE_ARRAY:
		for pile in piles:
			if typeof(pile) == TYPE_DICTIONARY and not Inventory.item(String(pile.get("item", ""))).is_empty() and int(pile.get("count", 0)) > 0:
				ground.append({"item": String(pile.item), "count": int(pile.count), "x": float(pile.get("x", 0.0)), "y": float(pile.get("y", 0.0))})
	var conts = d.get("containers", {})
	if typeof(conts) == TYPE_DICTIONARY:
		for id in conts:
			if typeof(conts[id]) == TYPE_DICTIONARY:
				containers[String(id)] = Inventory.from_dict(conts[id])
	var ids = d.get("searched", [])
	if typeof(ids) == TYPE_ARRAY:
		for id in ids:
			searched[String(id)] = true
	var cr = d.get("credit", {})
	if typeof(cr) == TYPE_DICTIONARY:
		for r in credit:
			credit[r] = float(cr.get(r, 0.0))
	var st = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st:
			stats[String(k)] = st[k]
	_full = bool(d.get("full", false))
	var nd = d.get("needs", {})    # (a save from before the needs has none: nothing owed, nothing told yet; the toasts then come once if she is already hungry)
	if typeof(nd) == TYPE_DICTIONARY:
		owed_meal = bool(nd.get("owed", false))
		for k in ["hungry", "thirsty"]:
			told[k] = bool(nd.get("told", {}).get(k, false)) if typeof(nd.get("told", {})) == TYPE_DICTIONARY else false
		for k in went:
			went[k] = bool(nd.get("went", {}).get(k, false)) if typeof(nd.get("went", {})) == TYPE_DICTIONARY else false
	var q = d.get("quick", [])    # (a save from before the quick slots has none: the belt is empty)
	if typeof(q) == TYPE_ARRAY:
		for i in mini((q as Array).size(), quick.size()):
			var qid := str(q[i])
			if qid == "" or not Inventory.item(qid).is_empty():
				quick[i] = qid
