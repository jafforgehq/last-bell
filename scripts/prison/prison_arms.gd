## EXPERIMENT (prison weapons, comp round): THE GUNS AND THE WEAPON RACK. Data: assets/data/prison_weapons.json (stats, noise radius, ammo cost, art of the SMG, the squad's numbers), merged over the shared game
## data of THIS process only (`merge`): the One House game never calls it, so its guns, goldens and tests are what they were. The rules that read a gun's own numbers are the town's (sim.shot_cost `cost`,
## dormant_dead `noise_radius_for` `noise`, the avatar's shot event `pitch`/`vol`); nothing else in the sim knows about these guns.
## PATTERN (inventory-system skill): the guns are ITEMS of the data-driven grid (`gun_shotgun`, `gun_service`, `gun_smg` in items.json, w by h cells, stack 1, no resource) for the SPARE gun and for guns FOUND in
## containers (a police place rolls them: prison_raids.json), and the weapon in her hands is plain state (`main`) because a Resource per gun would add a second item system next to the one the pack already is.
## REJECTED: a Resource per weapon (the grid, loot windows, stash and the bank all read items.json), and a ammo stock per gun (a second set of rows in the stash, the stores, the econ lab and the loot lab).
## AMMO: ONE stock `ammo` for every gun; the gun's own `cost` says how much a round takes: 3 shells, 4 rifle rounds or 10 SMG rounds to a unit. The economy lab and the loot lab count units and are unchanged.
## THE RACK (`armory`): {gun id: how many the base owns}. Going out takes the main gun and the spare out of it; a live return puts them back and every gun item in the pack or in a companion's bag with them
## (guns found in raids); her death loses the guns she carried (the quartermaster keeps one old pump shotgun when nothing is left). Keys in a raid: B swaps the gun in her hands with the spare in the pack.
extends RefCounted

const Inventory := preload("res://scripts/sim/inventory.gd")
const PATH := "res://assets/data/prison_weapons.json"

static var _cfg := {}

var game
var armory := {}
var main := "shotgun"    # the gun in her hands (state, not an item)
var spare := ""    # the gun she will carry in the pack on the next raid ("" none)
var _spare_out := false
var mags := {}    # gun id -> rounds loaded in it, this raid (a gun that is swapped away keeps them)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if parsed is Dictionary else {}
	return _cfg


## Lays the prison's gun numbers over the shared data (once per process is enough, every call gives the same): stats over map.json's `weapons`, the hands of a new gun in `guns`, its picture in `weaponArt`,
## and the backpack's ammo item is called "Ammo" (it is every gun's).
static func merge(data: Dictionary) -> void:
	var c := cfg()
	for id in c.guns:
		var g: Dictionary = (data.weapons.get(id, {}) as Dictionary).duplicate()
		for k in c.guns[id]:
			g[k] = c.guns[id][k]
		data.weapons[id] = g
	for id in c.gun_art:
		var a: Dictionary = c.gun_art[id]
		data.weaponArt.files[id] = String(a.file)
		data.guns[id] = {"muzzle": float(a.muzzle), "front": float(a.front), "rest": float(a.rest)}
	var sh: Dictionary = Inventory.item("shells")
	if not sh.is_empty():
		sh["name"] = "Ammo"
		sh["desc"] = "Rounds for every gun: one unit loads 3 shells, 4 rifle rounds or 10 SMG rounds. The reload takes them from the pack."


func _init(g) -> void:
	game = g
	armory = (cfg().armory_start as Dictionary).duplicate()
	if game.args.has("gun") and cfg().guns.has(String(game.args.gun)):    # staging: --gun=smg
		main = String(game.args.gun)
		armory[main] = maxi(1, int(armory.get(main, 0)))
	if game.args.has("spare") and cfg().guns.has(String(game.args.spare)):    # staging: --spare=service
		spare = String(game.args.spare)


func order() -> Array:
	return cfg().order


func gun_name(id: String) -> String:
	return String(game.data.weapons[id].get("name", id))


func owned(id: String) -> int:
	return int(armory.get(id, 0))


## Guns she can pick as the one in her hands: the rack's, in the data's order.
func choices() -> Array:
	var out: Array = []
	for id in order():
		if owned(String(id)) > 0:
			out.append(String(id))
	return out


## The numbers a player wants to read: "8 rounds, 4 to a unit, reach 17".
func stats_line(id: String) -> String:
	var g: Dictionary = game.data.weapons[id]
	var per := int(round(1.0 / maxf(float(g.get("cost", 0.2)), 0.001)))
	var rate := 1.0 / maxf(float(g.cooldown), 0.01)
	return "%d rounds, %d to a unit of ammo, %.1f shots a second, reach %d, heard %d tiles away" % [int(g.mag), per, rate, int(float(g.range)), int(float(g.get("noise", 12.0)))]


func blurb(id: String) -> String:
	return String(cfg().guns[id].get("blurb", ""))


## The rack's gun `main` is not there (the last of its kind was lost): the first one that is, else a pump shotgun.
func settle() -> void:
	var total := 0
	for id in armory:
		total += int(armory[id])
	if total <= 0:
		armory["shotgun"] = 1
	if owned(main) <= 0 and not choices().is_empty():
		main = String(choices()[0])
	if spare != "" and (owned(spare) <= (1 if spare == main else 0)):
		spare = ""


## Puts `id` in a person's hands (the magazine as it was left, else full): the gun, its rounds, the picture of the pawn.
func set_gun(p, id: String) -> void:
	mags[String(p.weapon)] = int(p.mag)
	p.weapon = id
	p.gun = game.data.weapons[id]
	p.mag = int(mags.get(id, int(p.gun.get("mag", 0))))
	p.reloading = 0.0
	p.cooldown = 0.4
	if game.pawn_nodes.has(p):
		game.pawn_nodes[p].set_weapon(game.data, id)


## A new stage (the base, a raid) has made Ruth with the data's gun: she takes the chosen one, loaded.
func apply(p) -> void:
	settle()
	mags = {}
	p.weapon = main
	p.gun = game.data.weapons[main]
	p.mag = int(p.gun.get("mag", 0))
	p.aim = float(game.data.guns[main].rest)


## A raid starts (the pack is filled): the main gun and the spare leave the rack, the spare lies in the pack.
func carry_out() -> void:
	armory[main] = owned(main) - 1
	if spare != "":
		var left := Inventory.auto_add(game.pack.grid, "gun_" + spare, 1)
		if left > 0:
			game._say("No room for the spare %s in the pack." % gun_name(spare), 4.0)
		else:
			_spare_out = true
			armory[spare] = owned(spare) - 1
			if game.pack.inv != null:
				game.pack.inv.version = int(game.pack.inv.version) + 1


## Guns in grids (the pack, a bag) go to the rack. How many.
func collect(grids: Array) -> int:
	var n := 0
	for g in grids:
		var i := 0
		while i < (g.cells as Array).size():
			var pl: Dictionary = g.cells[i]
			var gid := String(pl.item).trim_prefix("gun_")
			if String(pl.item).begins_with("gun_") and cfg().guns.has(gid):
				armory[gid] = owned(gid) + int(pl.count)
				n += int(pl.count)
				(g.cells as Array).remove_at(i)
			else:
				i += 1
	return n


## The raid ends alive: her main gun and every gun item in a grid go back to the rack. Returns how many guns she brought that she did not take out.
func land(grids: Array) -> int:
	armory[main] = owned(main) + 1
	var n := collect(grids) - (1 if _spare_out else 0)
	_spare_out = false
	spare = ""
	settle()
	return maxi(n, 0)


## The raid ends in her death: what she carried is gone (the pack's items go with `pack.lose`).
func lost() -> void:
	_spare_out = false
	spare = ""
	settle()


## B: the gun in her hands and the spare in the pack change places. False when there is no spare or it would not fit.
func swap(p) -> bool:
	var grid: Dictionary = game.pack.grid
	var idx := -1
	for i in (grid.cells as Array).size():
		if String(grid.cells[i].item).begins_with("gun_"):
			idx = i
			break
	if idx < 0:
		return false
	var old := String(p.weapon)
	var want := String(grid.cells[idx].item).trim_prefix("gun_")
	var saved: Dictionary = Inventory.to_dict(grid)
	Inventory.remove(grid, idx)
	if Inventory.auto_add(grid, "gun_" + old, 1) > 0:
		game.pack.grid = Inventory.from_dict(saved)    # (it does not fit: nothing changed)
		game.pack.inv.pack = game.pack.grid
		return false
	set_gun(p, want)
	main = want
	game.pack.inv.version = int(game.pack.inv.version) + 1
	return true


func has_spare_in_pack() -> bool:
	for pl in game.pack.grid.cells:
		if String(pl.item).begins_with("gun_"):
			return true
	return false


## SAVE hook (prison_save.gd): the rack, the gun in her hands and the spare.
func to_dict() -> Dictionary:
	return {"armory": armory.duplicate(), "main": main, "spare": spare}


func from_dict(d: Dictionary) -> void:
	armory = {}
	for k in (d.get("armory", {}) as Dictionary):
		armory[String(k)] = int(d.armory[k])
	main = String(d.get("main", main))
	spare = String(d.get("spare", ""))
