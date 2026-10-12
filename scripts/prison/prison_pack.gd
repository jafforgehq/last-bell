## EXPERIMENT (prison pack): the One House backpack, reused as it is, in the prison game. The rules are the town's own `sim.inv` (scripts/town/inv.gd: pack grid, belt, loot windows, stash) and the
## windows are the real `InvUi` (scripts/ui/inv_ui.gd: backpack, Ruth's outline, belt keys 1 to 4, loot window, stash window). Nothing of them is copied; this file only adapts the host:
##   - InvUi wants a "main" with a `hud` (a bare real `Hud` control is enough: the window helpers live there), a `sim`, and screen maths: this object is that main.
##   - the prison builds a NEW sim for every raid and for the base, so the grid and the belt live HERE and are handed to each new `sim.inv` (`attach`).
##   - `PInv` is the town's `inv.gd` with one change: the stash sits at the base's stores (the town's base module does not exist here).
## The base stock dictionary stays the source of truth: the stash window moves units between `game.stores` (the base sim shares that very dictionary) and the grid as items.
## Raid: the pack IS the loadout (the standard kit is withdrawn when she goes out with an empty pack). Extract: every item that stands for a resource goes back into the stock, then the stock is banked.
## Die: grid and belt are emptied.
extends RefCounted

const Inventory := preload("res://scripts/sim/inventory.gd")
const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvUi := preload("res://scripts/ui/inv_ui.gd")
const Hud := preload("res://scripts/ui/hud.gd")

## What she is handed when she goes out with nothing in the pack (store units).
const KIT := {"ammo": 40, "meds": 1, "food": 1, "water": 1}
## The belt takes these, in this order, while a slot is free.
const BELT := ["bandage", "canned_food", "water_bottle", "medkit", "ration_pack", "water_jug"]


## The town's inventory rules, with the stash where the prison keeps its stores.
class PInv:
	extends "res://scripts/town/inv.gd"
	var stash_at := Vector2.INF

	func _stash_pos() -> Vector2:
		return stash_at

	func can_stash() -> bool:
		return stash_open


## A bare Hud: the windows borrow its colours and builders; its toasts go to the game's message line.
class PHud:
	extends Hud
	var say := Callable()

	func toast(text: String, _level: String = "info") -> void:
		if say.is_valid():
			say.call(text, 3.0)


var game
var sim
var inv
var ui
var hud    # (read by InvUi as main.hud)
var menu_open := false    # (read by InvUi)
var town = null    # (read by InvUi: none, so the town's cards are not asked for)
var zoom_px: float:
	get:
		return game.zoom_px
## The backpack and the belt: they outlive the sims.
var grid: Dictionary = Inventory.make_pack()
var quick: Array = ["", "", "", ""]
var _flag := ""
var _frames := 0
var _full_t := -1.0


func _init(g) -> void:
	game = g
	_flag = String(g.args.get("pack", ""))


# ---------------------------------------------------------------------------- host maths (InvUi) --

func view_pos(p) -> Vector2:
	return Vector2(p.x, p.y)


func _tile_to_screen(t: Vector2) -> Vector2:
	return (t - game.cam_center) * game.zoom_px + game._vp() / 2.0


# ------------------------------------------------------------------------------------- lifecycle --

## Puts the pack into a new sim (the base's or a raid's) and builds the windows on it. `stash_at`: where the stash is (the base), else INF.
func attach(s, stash_at: Vector2 = Vector2.INF) -> void:
	detach()
	sim = s
	inv = PInv.new()
	s.inv = inv    # (the sim steps its parts by name: this one is stepped from now on)
	inv.setup(s)
	inv.begin({})
	inv.pack = grid
	inv.quick = quick
	inv.stash_at = stash_at
	var a := String(game.args.get("auto", ""))
	inv.auto_take = a != "" and a != "loot" and a != "play"    # (a scripted run has the lab's hand that takes everything)
	hud = PHud.new()
	hud.say = Callable(game, "_say")
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud.add_child(hud)
	hud.size = game._vp()
	ui = InvUi.new()
	ui.on_ready(self)
	_frames = 0


func detach() -> void:
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
	hud = null
	ui = null
	sim = null


func frame(dt: float) -> void:
	if ui == null or sim == null:
		return
	_frames += 1
	hud.size = game._vp()
	ui.on_frame(dt)
	if _frames == 5 and _flag == "stash" and game.mode == "base":    # (the stash only opens beside the stores)
		game.run.avatar_p.x = float(game.base.stations.stores.x)
		game.run.avatar_p.y = float(game.base.stations.stores.y) + 1.0
	if _frames == 5 and _flag.begins_with("search") and game.mode == "raid":    # (the nearest container that holds something, not an empty car)
		var best = null
		for c in game.town.containers:
			if not (c.loot as Dictionary).is_empty() and (best == null or Vector2(c.pos).distance_to(Vector2(game.run.avatar_p.x, game.run.avatar_p.y)) < Vector2(best.pos).distance_to(Vector2(game.run.avatar_p.x, game.run.avatar_p.y))):
				best = c
		if best != null:
			game.run.avatar_p.x = float(best.pos.x)
			game.run.avatar_p.y = float(best.pos.y)
	if _frames == 12:
		if _flag == "open" or _flag == "stash":
			ui.open_pack()
		if _flag == "stash":
			inv.open_stash()
	if _flag.begins_with("search") and _frames == 15:    # (a staged search of the first thing in reach; "search-full" fills the pack first)
		if _flag == "search-full":
			for n in 300:    # (until every cell is used: stacks merge, so many rounds)
				Inventory.auto_add(grid, "water_jug", 1)
				Inventory.auto_add(grid, "water_bottle", 1)
				Inventory.auto_add(grid, "ration_pack", 1)
				Inventory.auto_add(grid, "canned_food", 4)
				Inventory.auto_add(grid, "medkit", 1)
				Inventory.auto_add(grid, "bandage", 1)
		for c in sim.uses.candidates(sim.avatar.player()):
			if String(c.kind) == "container":
				sim.uses.use(c)
				break
	if _flag.begins_with("search") and _frames == 140 and inv.open_id != "" and _flag == "search-full":
		inv.take_all_open()
	var al = sim.alerts.get("pack-full")
	if al != null and float(al.t) != _full_t:
		_full_t = float(al.t)
		game._say("Pack full. %s" % String(al.sub), 3.5)


func on_event(e: Dictionary) -> void:
	if ui != null:
		ui.on_event(e)


## A key for the backpack (Tab, I, 1 to 4, Esc while a window is up, Space for take all, R while dragging). True when it was used.
func key(ev: InputEvent) -> bool:
	return ui != null and ui.on_key(ev)


## The mouse is over an open window or holds an item: the gun must not fire through it.
func blocks_fire() -> bool:
	if ui == null or not ui.is_open():
		return false
	if not ui.drag.is_empty():
		return true
	var m: Vector2 = game.get_viewport().get_mouse_position()
	for w in ui._open_windows():
		if Rect2(w.position, w.size).grow(6.0).has_point(m):
			return true
	return false


func close() -> void:
	if ui != null:
		ui.close_all()


func open_stash() -> void:
	if inv != null and inv.stash_at != Vector2.INF:
		inv.open_stash()


# ------------------------------------------------------------------------------------ the economy --

## Going out with nothing in the pack: the standard kit from the stores. The belt is filled from what she carries either way. Returns a line for the message ("" when she chose her own).
func kit(stores: Dictionary, custom: Dictionary = {}) -> String:
	var line := ""
	if Inventory.is_empty(grid) or not custom.is_empty():
		var want: Dictionary = custom if not custom.is_empty() else KIT
		line = "The quartermaster hands you the %s kit. " % ("loadout you chose" if not custom.is_empty() else "standard")
		for r in want:
			if int(want[r]) <= 0:
				continue
			var got := Inventory.withdraw(stores, grid, String(r), int(want[r]))
			if got < int(want[r]) and r == "ammo":    # (the stores hold less than the kit: she gets what is there)
				line = "The stores could only spare %d rounds. " % got
	for id in BELT:
		if InvApi.count_of(grid, id) > 0 and not quick.has(id):
			var slot := quick.find("")
			if slot < 0:
				break
			quick[slot] = id
	return line


## Coming back alive: every item that stands for a resource goes into the raid sim's stock (the caller banks that). {res: units} of what went.
func bank() -> Dictionary:
	if inv == null:
		return {}
	var got: Dictionary = inv.deposit_all(true)
	for r in inv.credit:
		inv.credit[r] = 0.0
	for i in quick.size():
		quick[i] = ""    # (the belt points at items that are in the stores now)
	return got


## Dying: the pack and the belt are gone. How many stacks were lost.
func lose() -> int:
	var n := (grid.cells as Array).size()
	(grid.cells as Array).clear()
	for i in quick.size():
		quick[i] = ""
	if inv != null:
		inv.version = int(inv.version) + 1
	return n


## One line for the HUD: cells used, and what she carries by resource.
func status() -> String:
	var t := {}
	for r in ["ammo", "food", "water", "meds"]:
		t[r] = Inventory.units(grid, r)
	return "Pack %d/%d cells  ammo %d  food %d  water %d  meds %d    (I: backpack, 1-4: belt)" % [Inventory.used_cells(grid), Inventory.cell_count(grid), t.ammo, t.food, t.water, t.meds]
