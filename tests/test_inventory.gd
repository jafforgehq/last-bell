extends "res://tests/case.gd"
## INV-CORE (scripts/sim/inventory.gd, scripts/town/inv.gd, assets/data/items.json; the design is docs/superpowers/specs/2026-10-09-inventory-design.md): the grid logic (placement, rotation,
## stacking, moving, splitting, quick moves), the units that go to and come from the stores, the containers' items (the same units as the loot they were), and the pack in the town's rules:
## the search and its loot window, the full pack, the reload from the pack, her own bandage, her meals, the stash, and the save. Everything the pack does is gated to a One House run with a pack
## (`sim.inv.on`): the last test holds the other games to that.

const Helpers := preload("res://tests/helpers.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const CarLoot := preload("res://scripts/town/car_loot.gd")


# ---------------------------------------------------------------------- the grid --

func test_the_items_in_the_data_are_whole() -> void:
	var ids: Array = Inventory.item_ids()
	check(ids.size() >= 7, "the starting list is there: %d" % ids.size())
	for id in ids:
		var d := Inventory.item(String(id))
		if String(id).begins_with("gun_") or String(id) == "note":    # (the prison game's guns and the story's letter: an item of its own, no store, no units)
			check(int(d.w) >= 1 and int(d.h) >= 1 and int(d.stack) == 1 and String(d.res) == "" and String(d.use) == "none", "%s is a gun item: a size, one to a place, no store" % String(id))
			continue
		if String(id) == "distraction" or String(id) == "flare":    # (the prison game's bottles and cans: a stack, no store, no units; G throws one)
			check(int(d.w) >= 1 and int(d.h) >= 1 and int(d.stack) >= 1 and String(d.res) == "" and String(d.use) == "none", "distraction is a throwable stack: a size, no store")
			continue
		check(int(d.w) >= 1 and int(d.h) >= 1 and int(d.stack) >= 1 and int(d.units) >= 1, "%s has a size, a stack and units" % String(id))
		check(["ammo", "food", "water", "meds", "parts", "fuel"].has(String(d.res)), "%s stands for a store: %s" % [String(id), String(d.res)])
		check(["eat", "drink", "bandage", "none"].has(String(d.use)), "%s has a use: %s" % [String(id), String(d.use)])
	eq(Inventory.size_of("water_jug"), Vector2i(2, 2), "a jug is two by two")
	eq(Inventory.size_of("water_bottle"), Vector2i(1, 1), "a bottle is one cell (PH10: it was two)")
	eq(Inventory.size_of("ration_pack", true), Vector2i(2, 1), "a ration pack turned lies two by one")
	var pack := Inventory.make_pack()
	eq([int(pack.w), int(pack.h)], [8, 4], "the pack is eight by four")
	check(Inventory.item("nothing").is_empty() and not Inventory.can_place(pack, "nothing", 1, 0, 0), "an unknown item is never placed")


func test_the_prison_flare_and_event_odds_data() -> void:
	check(Inventory.item("flare").size() > 0 and Inventory.stack_of("flare") >= 2, "the signal flare is an item that stacks")
	var items: Array = Inventory.items_for_loot({"flare": 2}, 1)
	check(items.size() == 1 and String(items[0].item) == "flare" and int(items[0].count) == 2, "a flare found in a raid is a pack item (%s)" % [items])
	var raids = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/prison_raids.json"))
	var n := 0
	for k in ["garage", "petrol", "police", "hardware"]:
		for e in raids.rolls[k]:
			if e[0] == "flare":
				n += 1
	check(n == 4, "four place tables can hold a flare (%d)" % n)
	var ev = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/prison_events.json"))
	for c in ev.cards:
		for ch in c.choices:
			var odds := 0.0
			for op in ([ch.effects.person] if ch.get("effects", {}).get("person") is Dictionary else []):
				odds = float(op.get("hurt_odds", 0.0))
			if odds > 0.0:
				check(ch.has("chance") and is_equal_approx(float(ch.chance[0].p), odds), "%s: the shown chance is the rolled one" % String(ch.id))


## PLAYTEST 4: Ruth starts with five allies, each with a bio and a base job, and the stores of the clear always pay for the first project (the water pump).
func test_the_prison_starts_with_five_allies_and_the_first_project_affordable() -> void:
	var Crew = load("res://scripts/prison/prison_crew.gd")
	var G = load("res://scripts/prison/prison_game.gd")
	eq(Crew.ALLIES.size(), 5, "five allies walk in with Ruth")
	eq(Crew.CREW_FROM_ALLIES.size(), 5, "and all five join the base crew")
	var bios = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/prison_bios.json"))
	var proj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/prison_projects.json"))
	for a in Crew.ALLIES:
		check(bios.people.has(String(a.name)), "%s has a bio" % String(a.name))
		check(proj.crew_role.has(String(a.id)), "%s has a base role" % String(a.name))
	var water := 0.0
	for p in proj.projects:
		if String(p.id) == "water1":
			water = float(p.cost.scrap)
	check(float(G.CLEAR_STORES.scrap) >= water, "the clear's own stores pay for the water pump (%d of %d scrap)" % [int(G.CLEAR_STORES.scrap), int(water)])


func test_placement_bounds_overlap_and_rotation() -> void:
	var g := Inventory.make_grid(3, 2)
	check(Inventory.can_place(g, "water_jug", 1, 0, 0), "a jug fits in the corner")
	check(not Inventory.can_place(g, "water_jug", 1, 2, 0), "not over the right edge")
	check(not Inventory.can_place(g, "water_jug", 1, 0, 1), "not over the bottom")
	check(not Inventory.can_place(g, "water_jug", 1, -1, 0), "not outside on the left")
	eq(Inventory.place(g, "water_jug", 1, 0, 0), 0, "placed: index 0")
	check(not Inventory.can_place(g, "canned_food", 1, 1, 1), "cell (1, 1) is under the jug")
	check(Inventory.can_place(g, "canned_food", 1, 2, 1), "a free cell takes a can")
	check(not Inventory.can_place(g, "canned_food", 5, 2, 0), "a can's stack is four: not five in one place")
	check(not Inventory.can_place(g, "canned_food", 0, 2, 0), "nothing is not a placement")
	# rotation: a ration pack (1 by 2) in a grid one row high fits only lying down
	var flat := Inventory.make_grid(2, 1)
	check(not Inventory.can_place(flat, "ration_pack", 1, 0, 0, false), "upright it does not fit")
	check(Inventory.can_place(flat, "ration_pack", 1, 0, 0, true), "lying it does")
	eq(Inventory.auto_add(flat, "ration_pack", 1), 0, "auto_add turns it when that is the only way")
	check(bool(flat.cells[0].rot), "and says it is turned")
	eq(Inventory.placement_at(g, 1, 1), 0, "the jug covers (1, 1)")
	eq(Inventory.placement_at(g, 2, 0), -1, "and not (2, 0)")
	var gone := Inventory.remove(g, 0)
	eq(String(gone.item), "water_jug", "remove gives the placement back")
	check(Inventory.is_empty(g) and Inventory.remove(g, 3).is_empty(), "and the grid is empty; a bad index gives {}")


func test_stacks_fill_before_new_places_and_the_count_is_kept() -> void:
	var g := Inventory.make_grid(2, 1)
	eq(Inventory.auto_add(g, "shells", 30), 0, "30 shells go in")
	eq(g.cells.size(), 2, "24 and 6: two places")
	eq(int(g.cells[0].count) + int(g.cells[1].count), 30, "nothing is lost")
	eq(Inventory.auto_add(g, "shells", 18), 0, "18 more fill the second stack")
	eq([int(g.cells[0].count), int(g.cells[1].count)], [24, 24], "both full")
	eq(Inventory.auto_add(g, "shells", 5), 5, "no room: 5 left over")
	eq(Inventory.auto_add(g, "canned_food", 2), 2, "and a can has no cell either")
	eq(Inventory.units(g, "ammo"), 48, "the units are the rounds")
	eq(Inventory.room_for(Inventory.make_grid(1, 1), "canned_food", 9), 4, "a one-cell grid takes one stack of cans")


func test_move_merge_and_split() -> void:
	var a := Inventory.make_grid(4, 2)
	var b := Inventory.make_grid(2, 2)
	Inventory.place(a, "shells", 10, 0, 0)
	Inventory.place(a, "shells", 20, 1, 0)
	Inventory.place(a, "ration_pack", 1, 3, 0)
	# inside one grid
	check(Inventory.move(a, 0, a, 0, 1), "to a free cell of the same grid")
	eq([int(a.cells[0].x), int(a.cells[0].y)], [0, 1], "it is there now")
	check(not Inventory.move(a, 0, a, 3, 0), "not onto a ration pack, an item of another kind")
	# onto a stack of the same kind: merges what fits (24 - 20 = 4)
	check(Inventory.move(a, 0, a, 1, 0), "onto a stack of the same item")
	eq([int(a.cells[0].count), int(a.cells[1].count)], [6, 24], "4 moved, 6 stay")
	check(Inventory.merge(a, 0, 1) == 0, "a full stack takes no more")
	# to another grid
	check(Inventory.move(a, 2, b, 1, 0, false), "the ration pack goes to the other grid")
	eq(a.cells.size(), 2, "and is gone from the first")
	eq(String(b.cells[0].item), "ration_pack", "it is in the second")
	check(not Inventory.move(a, 0, b, 1, 1), "a ration pack sits at (1, 0)-(1, 1): the cell under it is taken")
	# split: 24 in two
	var s := Inventory.split(a, 1, 10)
	check(s >= 0, "split makes a place for the 10")
	eq([int(a.cells[1].count), int(a.cells[s].count)], [14, 10], "14 and 10")
	check(Inventory.split(a, 1, 14) < 0 and Inventory.split(a, 1, 0) < 0, "a split of all or none is refused")
	eq(Inventory.merge(a, s, 1), 10, "merged back: 10 moved")
	eq(Inventory.units(a, "ammo"), 30, "30 rounds all through")


func test_quick_move_and_take_all_keep_what_does_not_fit() -> void:
	var from := Inventory.make_grid(4, 4)
	var to := Inventory.make_grid(2, 2)
	Inventory.auto_add(from, "water_jug", 1)
	Inventory.auto_add(from, "water_jug", 1)
	Inventory.auto_add(from, "shells", 7)
	Inventory.auto_add(from, "canned_food", 6)
	eq(Inventory.units(from, "water"), 8, "two jugs: 8 water")
	var moved := Inventory.take_all(from, to)
	check(moved > 0, "something moved")
	eq(Inventory.used_cells(to) <= 4, true, "the target is not over full")
	eq(Inventory.units(from, "water") + Inventory.units(to, "water"), 8, "no water is lost")
	eq(Inventory.units(from, "ammo") + Inventory.units(to, "ammo"), 7, "no shell is lost")
	eq(Inventory.units(from, "food") + Inventory.units(to, "food"), 6, "no can is lost")
	check(Inventory.units(from, "water") >= 4, "the second jug could not go in")
	var empty_to := Inventory.make_grid(1, 1)
	Inventory.place(empty_to, "shells", 24, 0, 0)
	check(not Inventory.quick_move(from, 0, empty_to) or Inventory.units(empty_to, "ammo") >= 24, "a full target takes nothing more of the same")


func test_units_are_taken_exactly_and_a_big_item_only_when_allowed() -> void:
	var g := Inventory.make_grid(4, 4)
	Inventory.auto_add(g, "ration_pack", 2)
	Inventory.auto_add(g, "canned_food", 3)
	eq(Inventory.units(g, "food"), 9, "two rations and three cans: 9")
	eq(Inventory.take_units(g, "food", 2), 2, "two units: cans first (the smallest)")
	eq(Inventory.units(g, "food"), 7, "7 left")
	eq(Inventory.take_units(g, "food", 2), 1, "one can left, and a ration is not broken for two: 1")
	eq(Inventory.take_units(g, "food", 2), 0, "only rations of 3 now: nothing without 'allow_over'")
	eq(Inventory.take_units(g, "food", 2, true), 3, "with allow_over a ration goes for the two (3 units out)")
	eq(Inventory.units(g, "food"), 3, "one ration left")
	eq(Inventory.take_units(g, "water", 5), 0, "none of a resource there is none")
	check(g.cells.size() == 1, "the empty placements are gone")


func test_deposit_and_withdraw_move_the_same_units() -> void:
	var g := Inventory.make_grid(8, 4)
	var stores := {"ammo": 10.0, "food": 5.0, "water": 9.0, "meds": 0.0, "scrap": 3.0}
	Inventory.auto_add(g, "shells", 30)
	Inventory.auto_add(g, "water_jug", 2)
	Inventory.auto_add(g, "water_bottle", 3)
	Inventory.auto_add(g, "medkit", 1)
	var before := {"ammo": 30, "water": 11, "meds": 3}
	var put := Inventory.deposit_all(g, stores)
	eq(put, before, "what was deposited, by resource")
	check(Inventory.is_empty(g), "the pack is empty")
	near(float(stores.ammo), 40.0, 0.001, "ammo 10 + 30")
	near(float(stores.water), 20.0, 0.001, "water 9 + 11")
	near(float(stores.meds), 3.0, 0.001, "meds 0 + 3")
	near(float(stores.scrap), 3.0, 0.001, "scrap is not an item: untouched")
	# withdraw: units out of the stores, as items
	eq(Inventory.withdraw(stores, g, "water", 9), 9, "9 water moved")
	eq(Inventory.units(g, "water"), 9, "9 water in the pack")
	var kinds: Dictionary = {}
	for p in g.cells:
		kinds[String(p.item)] = int(kinds.get(String(p.item), 0)) + int(p.count)
	eq(kinds, {"water_jug": 2, "water_bottle": 1}, "two jugs and a bottle (the biggest first)")
	near(float(stores.water), 11.0, 0.001, "water out of the stores")
	eq(Inventory.withdraw(stores, g, "meds", 99), 3, "no more than the stores hold")
	near(float(stores.meds), 0.0, 0.001, "meds are all out")
	# a pack with no room moves nothing and the stores keep it
	var tiny := Inventory.make_grid(1, 1)
	Inventory.place(tiny, "bandage", 1, 0, 0)
	eq(Inventory.withdraw(stores, tiny, "water", 4), 0, "a pack with no room takes no jug and no bottle")
	near(float(stores.water), 11.0, 0.001, "the stores still hold it")
	var one := Inventory.make_grid(1, 1)
	eq(Inventory.withdraw(stores, one, "water", 4), 1, "one cell takes a single bottle (a bottle is one cell now) and no jug")
	near(float(stores.water), 10.0, 0.001, "and the stores gave only that")
	one = Inventory.make_grid(1, 1)
	eq(Inventory.withdraw(stores, one, "ammo", 30), 24, "one cell takes one stack of 24 shells")
	near(float(stores.ammo), 16.0, 0.001, "and the stores gave only those")


func test_a_grid_round_trips_through_json_and_a_bad_save_is_cleaned() -> void:
	var g := Inventory.make_grid(8, 4)
	Inventory.auto_add(g, "shells", 40)
	Inventory.auto_add(g, "water_jug", 1)
	Inventory.auto_add(g, "medkit", 1)
	Inventory.place(g, "water_bottle", 1, 7, 2, false)
	Inventory.place(g, "ration_pack", 1, 5, 2, true)
	var text := JSON.stringify(Inventory.to_dict(g))
	var back := Inventory.from_dict(JSON.parse_string(text))
	eq(Inventory.to_dict(back), Inventory.to_dict(g), "the same grid after JSON")
	check(bool(back.cells[back.cells.size() - 1].rot), "the turn is kept")
	var bad := {"w": 2, "h": 2, "cells": [
		{"item": "shells", "x": 0, "y": 0, "rot": 0, "count": 99},
		{"item": "shells", "x": 0, "y": 0, "rot": 0, "count": 3},
		{"item": "ghost_item", "x": 1, "y": 1, "rot": 0, "count": 1},
		{"item": "canned_food", "x": 5, "y": 5, "rot": 0, "count": 1},
		{"item": "canned_food", "x": 1, "y": 1, "rot": 1, "count": 2},
		"junk"]}
	var fixed := Inventory.from_dict(bad)
	eq(fixed.cells.size(), 2, "the overlap, the unknown item, the stray and the junk are dropped")
	eq(int(fixed.cells[0].count), 24, "a count over the stack is cut to it")


# ----------------------------------------------------------- the containers' items --

## The units of a loot dictionary, all resources.
func _units_of(loot: Dictionary) -> int:
	var n := 0
	for k in loot:
		n += int(loot[k])
	return n


func test_a_loot_becomes_items_of_exactly_its_units() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var shapes := {}
	for i in 300:
		var loot := {}
		for r in ["ammo", "food", "water", "meds", "scrap"]:
			if rng.randf() < 0.5:
				loot[r] = rng.randi_range(1, 9)
		var items := Inventory.items_for_loot(loot, i * 13)
		var sum := 0
		for e in items:
			sum += int(e.count) * Inventory.units_of(String(e.item))
			shapes[String(e.item)] = true
		var loose := Inventory.loose_units(loot)
		for k in loose:
			sum += int(loose[k])
		eq(sum, _units_of(loot), "loot %s: the items and the scrap are its units" % str(loot))
		eq(Inventory.items_for_loot(loot, i * 13), items, "and the same key gives the same items")
		var grid := Inventory.make_container("cupboard", loot, i * 13)
		for r in ["ammo", "food", "water", "meds"]:
			eq(Inventory.units(grid, r), int(loot.get(r, 0)), "the grid holds the loot's %s" % r)
	check(shapes.has("shells") and shapes.has("canned_food") and shapes.has("water_bottle") and shapes.has("bandage"), "the plain items turn up")
	check(shapes.has("ration_pack") and shapes.has("water_jug") and shapes.has("medkit"), "so do the big ones (a loot of three or four units sometimes is one)")


func test_every_container_of_the_towns_holds_its_loot_in_its_grid() -> void:
	for pair in [[1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [8, 2], [1, 6]]:
		var town: Dictionary = TownGen.make(int(pair[0]), {"blocks": int(pair[1])})
		var all: Array = (town.containers as Array).duplicate()
		all.append_array(CarLoot.containers(town))
		var before := 0
		var after := 0
		var grown := 0
		for c in all:
			before += _units_of(c.loot)
			var grid := Inventory.make_container(String(c.kind), c.loot, int(pair[0]) * 31 + String(c.id).hash())
			for r in ["ammo", "food", "water", "meds"]:
				after += Inventory.units(grid, r)
			var loose := Inventory.loose_units(c.loot)
			for k in loose:
				after += int(loose[k])
			grown += int(grid.get("grown", 0))
			check(int(grid.w) * int(grid.h) <= 36, "%s %s is a small grid" % [String(c.id), String(c.kind)])
		eq(after, before, "seed %d (%d blocks): the units of the items are the old loot's" % [int(pair[0]), int(pair[1])])
		eq(grown, 0, "seed %d: no container had to grow" % int(pair[0]))
		check(all.size() > 20, "there are containers to hold it: %d" % all.size())


## RAID SITES (scripts/prison/prison_site.gd): every place with a map of its own is whole: each container and the pickup point reachable on foot from the entry, the places named by the data,
## each container's loot rolled from its place type and held in a small grid, the open-air ones searched like the street's cars.
func test_every_raid_site_is_reachable_and_holds_its_loot() -> void:
	var Loot = load("res://scripts/prison/prison_loot.gd")
	var Site = load("res://scripts/prison/prison_site.gd")
	var Houses = load("res://scripts/town/houses.gd")
	var n := 0
	for id in Loot.place_ids():
		if not Site.LAYOUTS.has(String(Loot.place_cfg(id).get("layout", ""))):
			continue
		n += 1
		for s in [1, 2]:
			var t: Dictionary = Loot.make_town(s, id)
			check(t.has("site"), "%s has a map of its own" % id)
			var pls: Array = Loot.prepare(t, s, id)
			eq(Site.unreachable(t), [], "%s seed %d: every container and the pickup point can be reached" % [id, s])
			check((t.containers as Array).size() >= 15 and pls.size() >= 3, "%s seed %d: %d containers in %d places" % [id, s, (t.containers as Array).size(), pls.size()])
			for pl in pls:
				check(String(pl.get("name", "")) != "" and String(pl.get("hint", "")) != "", "%s: the place %s has a name and a hint" % [id, pl.get("name", "?")])
			var outdoor := 0
			for c in t.containers:
				check(c.has("place"), "%s %s rolled from a place type" % [id, c.id])
				var grid := Inventory.make_container(String(c.kind), c.loot, String(c.id).hash())
				check(int(grid.w) * int(grid.h) <= 36, "%s %s is a small grid" % [id, c.id])
				if bool(c.get("car", false)):
					outdoor += 1
			var hs = Houses.new()
			hs.use_town(t)
			eq(hs.cars.filter(func(c): return bool(c.get("car", false)) and String(c.id).begins_with("yd")).size(), outdoor, "%s: the loot in the open is searched like a car" % id)
	eq(n, 7, "seven places have a map of their own (the suburb keeps the streets)")


## RAID SITES (task W): Ruth is set down a few tiles in from the edge entry, toward the middle; a site has no street paint and every building a painted roof (the hospital a red cross);
## the message lanes move off Ruth and the crosshair (prison_game.gd `lane_dodge`).
func test_raid_sites_set_ruth_down_inside_and_the_lanes_dodge_her() -> void:
	var Loot = load("res://scripts/prison/prison_loot.gd")
	var Site = load("res://scripts/prison/prison_site.gd")
	for id in Loot.place_ids():
		if not Site.LAYOUTS.has(String(Loot.place_cfg(id).get("layout", ""))):
			continue
		var t: Dictionary = Loot.make_town(1, id)
		var e := Vector2(t.entry.pos)
		var d := Vector2(t.site.drop)
		var mid := Vector2(32, 32)
		check(d.distance_to(e) >= 3.0 and d.distance_to(e) <= 12.0 and d.distance_to(mid) < e.distance_to(mid), "%s: set down at %s, a few tiles in from the entry %s" % [id, d, e])
		eq(Vector2(t.start.pos), d, "%s: the start is the drop" % id)
		eq(bool(t.data.get("road_grid", true)), false, "%s: no street paint on the site's roads" % id)
		for h in t.houses:
			check(h.get("roof_look") is Dictionary, "%s: %s has a painted roof" % [id, h.label])
		if id == "hospital":
			eq(String(t.houses[0].roof_look.get("sign", "")), "cross", "the hospital's roof has the red cross")
	var G = load("res://scripts/prison/prison_game.gd")
	var v := Vector2(1280, 720)
	var lane := Rect2(440, 580, 400, 50)
	eq(G.lane_dodge(lane, [Vector2(100, 100)], v, -1.0), 580.0, "nobody near: the prompt lane stays home")
	var y: float = G.lane_dodge(lane, [Vector2(640, 600)], v, -1.0)
	check(y + 50.0 <= 600.0 - G.LANE_CLEAR + 0.1, "Ruth on the prompt lane: it goes above her (%s)" % y)
	var top := Rect2(440, 60, 400, 60)
	var yb: float = G.lane_dodge(top, [Vector2(640, 90)], v, 1.0)
	check(yb >= 90.0 + G.LANE_CLEAR - 0.1, "Ruth under the banner: it goes below her (%s)" % yb)
	var short := Vector2(1024, 600)
	var home := Rect2(312, 125, 400, 100)
	check(G.lane_dodge(home, [Vector2(512, 300)], short, 1.0) >= 125.0, "a short window, Ruth in the middle: the banner never rises above its home under the top bar")


# ------------------------------------------------------------------- the pack in the rules --

func _p(sim):
	return sim.avatar.player()


func _at(sim, v: Vector2) -> void:
	var p = _p(sim)
	p.x = v.x
	p.y = v.y
	p.moving = false
	p.path = []


## A town game with a One House pack (the data's start pack and stores), the dead asleep, Ruth in the start house.
func _pack_game() -> Dictionary:
	var g := Helpers.town_game(1, {"home": true})
	var sim = g.sim
	sim.field.pause_wake = true
	var start: Dictionary = OneHouse.data().start
	for k in start.stock:
		sim.stock[String(k)] = float(start.stock[k])
	sim.inv.begin(start.pack)
	sim.events.clear()
	return g


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


## The first container of the start house, and Ruth beside it.
func _go_to_a_container(sim) -> String:
	var h: int = sim.houses.start_house()
	var cont: Dictionary = sim.houses.containers_of(h)[0]
	_at(sim, Vector2(cont.pos))
	Helpers.run(sim, 0.2)
	return String(cont.id)


func test_the_start_pack_is_the_data_and_the_stores_keep_the_rest() -> void:
	var g := _pack_game()
	var sim = g.sim
	var start: Dictionary = OneHouse.data().start
	var c: Dictionary = sim.inv.carried_totals()
	eq(int(c.ammo), 40, "she carries the forty shells")
	check(int(c.food) > 0 and int(c.water) > 0 and int(c.meds) > 0, "and food, water and bandages")
	check(Inventory.used_cells(sim.inv.pack) < 32, "with room left")
	near(float(sim.stock.ammo), float(start.stock.ammo), 0.001, "the stores hold what the data says")
	eq(sim.reserve_ammo(_p(sim)), 40.0, "her reserve ammo is the shells in the pack")
	near(sim.ammo_total(), 40.0 + float(sim.stock.ammo), 0.001, "the alert counts both")
	var s: Dictionary = sim.inv.store_totals()
	eq(int(s.scrap), int(start.stock.scrap), "store_totals reads the stores")
	eq(sim.inv.bar_totals(), c, "before the claim the top bar shows what she carries")
	g.world.free()


func test_searching_opens_the_window_reveals_one_item_at_a_time_and_waits_for_her() -> void:
	var g := _pack_game()
	var sim = g.sim
	var id := _go_to_a_container(sim)
	var cont: Dictionary = sim.houses.container(id)
	var items_before: int = sim.inv.items_left(id)
	var loot_units := 0
	for r in ["ammo", "food", "water", "meds"]:
		loot_units += int(cont.loot.get(r, 0))
	check(items_before > 0 or loot_units == 0, "the container has items (%d)" % items_before)
	var scrap_before := float(sim.stock.scrap)
	var cands: Array = sim.search.candidates(_p(sim))
	check(cands.size() >= 1 and String(cands[0].id) == id, "E offers the search")
	var r: Dictionary = sim.search.use(cands[0])
	check(bool(r.ok), "the search begins")
	eq(sim.inv.open_id, id, "the loot window is open on it")
	eq(sim.search.revealed(id), 0, "nothing shows yet")
	var secs: float = float(r.seconds)
	var seen_one_by_one := false
	var last := 0
	var t := 0.0
	while t < secs - 0.1:
		Helpers.run(sim, 0.1)
		t += 0.1
		var now: int = sim.search.revealed(id)
		check(now >= last and now <= items_before, "the count only goes up: %d" % now)
		if now > last and now < items_before:
			seen_one_by_one = true
		last = now
	if items_before >= 3:
		check(seen_one_by_one, "the items showed one at a time")
	Helpers.run(sim, 0.6)
	check(not sim.search.is_looted(id), "the container is not looted while the window is open")
	eq(sim.search.revealed(id), items_before, "all of it shows once searched")
	eq(_events(sim, "searched").size(), 1, "the search told once")
	var ev: Dictionary = _events(sim, "searched")[0]
	check(bool(ev.inv) and not bool(ev.taken), "and says it is the pack game and nothing is taken yet")
	var loose := Inventory.loose_units(cont.loot)
	near(float(sim.stock.scrap) - scrap_before, float(loose.get("scrap", 0)), 0.001, "the scrap went to the stores at once")
	eq(sim.inv.carried_totals().ammo, 40, "and the pack has taken nothing")
	# Take all: everything that fits; the container is looted when it is empty
	var n: int = sim.inv.take_all_open()
	eq(n, loot_units, "everything was taken: its units")
	check(sim.search.is_looted(id) and sim.search.is_spent(id), "emptied: looted and spent")
	eq(sim.inv.open_id, "", "and the window closes")
	var c: Dictionary = sim.inv.carried_totals()
	eq(int(c.ammo), 40 + int(cont.loot.get("ammo", 0)), "the shells are in the pack")
	eq(sim.search.candidates(_p(sim)).size(), 0, "nothing more to search or open")
	g.world.free()


func test_a_full_pack_leaves_items_in_the_container_and_the_shimmer_stays() -> void:
	var g := _pack_game()
	var sim = g.sim
	# fill the pack: every cell and every stack with room
	var pack: Dictionary = sim.inv.pack
	var more := true
	while more:
		more = false
		for it in ["water_jug", "water_bottle", "ration_pack", "medkit", "bandage", "canned_food", "shells"]:
			if Inventory.auto_add(pack, it, 1) == 0:
				more = true
	eq(Inventory.free_cells(pack), 0, "the pack is full")
	var h: int = sim.houses.start_house()
	var cont: Dictionary = {}
	for c in sim.houses.containers_of(h):
		var u := 0
		for r in ["food", "water", "meds"]:
			u += int(c.loot.get(r, 0))
		if u >= 2:
			cont = c
			break
	check(not cont.is_empty(), "a container with a few units of something that does not stack")
	var id := String(cont.id)
	_at(sim, Vector2(cont.pos))
	Helpers.run(sim, 0.2)
	var items0: int = sim.inv.items_left(id)
	var r: Dictionary = sim.search.use(sim.search.candidates(_p(sim))[0])
	check(bool(r.ok), "the search begins")
	Helpers.run(sim, float(r.seconds) + 0.5)
	var moved: int = sim.inv.take_all_open()
	eq(moved, 0, "a full pack takes nothing")
	eq(sim.inv.items_left(id), items0, "everything stays in the container")
	check(sim.alerts.has("pack-full"), "with a note")
	check(not sim.search.is_looted(id), "the window is still open: not looted")
	sim.inv.close_container()
	check(sim.search.is_looted(id), "closing the window marks it searched")
	check(sim.search.has_left(id) and not sim.search.is_spent(id), "but items are left: it is not spent (the shimmer returns)")
	check(sim.search.state(id).left > 0, "the state says how many")
	var again: Array = sim.search.candidates(_p(sim))
	check(again.size() == 1 and String(again[0].label).begins_with("Open the"), "E offers to open it again, with no search")
	check(not bool(again[0].session), "that is no session")
	# the pack is emptied into the stores (the stash), and the rest is taken at last
	sim.inv.deposit_all(true)
	var r2: Dictionary = sim.search.use(again[0])
	check(bool(r2.ok) and sim.inv.open_id == id, "the window opens again")
	var taken: int = sim.inv.take_all_open()
	check(taken > 0, "there is room now: %d taken" % taken)
	check(sim.search.is_spent(id), "emptied at last: spent")
	check(sim.search.candidates(_p(sim)).is_empty(), "nothing more to offer")
	g.world.free()


func test_the_crew_takes_what_is_left_in_a_container_to_the_stores() -> void:
	var g := _pack_game()
	var sim = g.sim
	var h: int = sim.houses.start_house()
	var cont: Dictionary = sim.houses.containers_of(h)[0]
	var id := String(cont.id)
	var want: Dictionary = sim.search.loot_of(id)
	var expect := {}
	for k in cont.loot:
		expect[String(k)] = int(cont.loot[k])
	eq(want, expect, "an untouched container holds its loot, units for units")
	# Ruth takes one item; what is left is what the crew find
	_go_to_a_container(sim)
	var r: Dictionary = sim.search.use(sim.search.candidates(_p(sim))[0])
	Helpers.run(sim, float(r.seconds) + 0.5)
	var pack_sum := func() -> int:
		var c: Dictionary = sim.inv.carried_totals()
		return int(c.ammo) + int(c.food) + int(c.water) + int(c.meds)
	var before_take: int = pack_sum.call()
	sim.inv.take_item(id, 0)
	var took: int = int(pack_sum.call()) - before_take
	var left: Dictionary = sim.search.loot_of(id)
	var total_left := 0
	for k in left:
		total_left += int(left[k])
	var item_units := 0
	for k in cont.loot:
		if k != "scrap":
			item_units += int(cont.loot[k])
	check(took > 0 or item_units == 0, "she took the first item")
	eq(total_left + took, item_units, "what the crew would find plus what she took is the loot's item units")
	check(not left.has("scrap"), "the scrap went to the stores at the search")
	var stock_before: Dictionary = sim.stock.duplicate()
	var got: Dictionary = sim.search.mark_looted(id)
	eq(got, left, "the crew get exactly that")
	for k in got:
		near(float(sim.stock[k]) - float(stock_before[k]), float(got[k]), 0.001, "in the stores: %s" % String(k))
	check(sim.search.is_looted(id) and sim.inv.open_id == "", "looted, and the window is shut")
	eq(sim.inv.items_left(id), 0, "nothing is left in it")
	check(Inventory.is_empty(sim.inv.grid_of(id)), "and asking for its grid does not make the items again")
	check(sim.search.is_spent(id), "it is spent")
	g.world.free()


func test_a_container_the_crew_search_untouched_gives_all_its_loot_to_the_stores() -> void:
	var g := _pack_game()
	var sim = g.sim
	var h: int = sim.houses.start_house()
	var cont: Dictionary = sim.houses.containers_of(h)[1]
	var id := String(cont.id)
	var before: Dictionary = sim.stock.duplicate()
	var got: Dictionary = sim.search.mark_looted(id)
	for k in cont.loot:
		eq(int(got.get(String(k), 0)), int(cont.loot[k]), "the crew find all the %s" % String(k))
		near(float(sim.stock[k]) - float(before[k]), float(cont.loot[k]), 0.001, "and it is in the stores")
	check(sim.search.is_spent(id) and Inventory.is_empty(sim.inv.grid_of(id)), "the container is spent and stays empty")
	eq(sim.search.mark_looted(id), {}, "a second search finds nothing")
	g.world.free()


func test_an_item_for_a_full_pack_lies_at_her_feet_and_can_be_picked_up() -> void:
	var g := _pack_game()
	var sim = g.sim
	var pack: Dictionary = sim.inv.pack
	while Inventory.auto_add(pack, "water_jug", 1) == 0:
		pass
	eq(sim.inv.give("water_jug", 1, "test"), 0, "a jug with no place goes in no cell")
	eq(sim.inv.ground.size(), 1, "it lies on the ground")
	var me = _p(sim)
	var pile: Dictionary = sim.inv.ground[0]
	near(float(pile.x), float(me.x), 0.001, "at her feet")
	eq(_events(sim, "pack_full").size(), 1, "an event for the window")
	check(sim.alerts.has("pack-full"), "and a note")
	eq(sim.inv.give("water_jug", 1), 0, "a second one joins the pile")
	eq(int(sim.inv.ground[0].count), 2, "two on the pile")
	var cs: Array = sim.inv.candidates(me)
	check(cs.size() == 1 and String(cs[0].label).begins_with("Pick up 2"), "E offers the pile")
	check(not sim.inv.pick_up(0), "nothing can be picked up while the pack is full")
	var jug := -1
	for i in pack.cells.size():
		if String(pack.cells[i].item) == "water_jug":
			jug = i
	check(sim.inv.drop(jug), "a jug put down")
	eq(int(sim.inv.ground[0].count), 3, "joins the pile")
	check(sim.inv.pick_up(0), "there is room for one now")
	eq(int(sim.inv.ground[0].count), 2, "two jugs stay on the ground")
	g.world.free()


func test_the_reload_takes_the_shells_from_the_pack_at_the_old_cost() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	var cap: int = int(me.gun.mag)
	var cost: float = sim.shot_cost(me)
	var stock_ammo := float(sim.stock.ammo)
	me.mag = 0
	sim.avatar.reload()
	Helpers.run(sim, 0.3)
	check(float(me.reloading) > 0.0, "R begins a reload")
	Helpers.run(sim, 4.0)
	eq(int(me.mag), cap, "the magazine is full")
	eq(float(sim.stock.ammo), stock_ammo, "the stores were not touched")
	var used: int = 40 - sim.inv.reserve_rounds()
	check(used == int(ceil(float(cap) * cost - 0.0001)), "a full magazine of %d shots costs %d whole shells (%.2f each)" % [cap, used, cost])
	# every round can be fired: 40 units are as many shots as the stores gave
	var shots := cap
	me.mag = 0
	while true:
		var got: int = sim.inv.load_shots(me, cap)
		if got <= 0:
			break
		shots += got
	check(shots >= int(floor(40.0 / cost)) - 1 and shots <= int(floor(40.0 / cost)) + 1, "40 units are %d shots (the stores gave %d)" % [shots, int(floor(40.0 / cost))])
	eq(sim.inv.reserve_rounds(), 0, "the pack has no shells left")
	check(not sim.ammo_ready(me) or int(me.mag) > 0, "and, with the magazine empty, no round to fire")
	me.mag = 0
	sim.avatar.reload()
	Helpers.run(sim, 0.3)
	eq(float(me.reloading), 0.0, "R with nothing to load begins nothing")
	eq(int(me.mag), 0, "and the magazine stays empty")
	eq(sim.gun_of(me).get("melee", false), true, "she swings the butt")
	g.world.free()


func test_a_shot_costs_the_pack_nothing_until_the_reload() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	me.mag = int(me.gun.mag)
	var units: int = sim.inv.reserve_rounds()
	var stock_ammo := float(sim.stock.ammo)
	sim.avatar.set_input(Vector2.ZERO, Vector2(me.x + 6.0, me.y), true)
	Helpers.run(sim, 0.5)
	sim.avatar.set_input(Vector2.ZERO, Vector2(me.x + 6.0, me.y), false)
	check(int(me.mag) < int(me.gun.mag), "she fired")
	eq(sim.inv.reserve_rounds(), units, "the pack still holds all its shells")
	eq(float(sim.stock.ammo), stock_ammo, "and the stores' ammo is the crew's alone")
	g.world.free()


func test_her_bandage_uses_the_pack_first_and_the_stores_only_at_the_base() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	sim.stock.meds = 5.0
	var pack_meds: int = sim.inv.carried_totals().meds
	check(pack_meds >= 2, "two bandages in the pack")
	near(sim.inv.meds_available(me), float(pack_meds), 0.001, "away from the base only the pack's medicine counts")
	me.bleeding = 1.0
	me.wounds = 1
	var bandage: Array = []
	for c in sim.interact.candidates():
		if String(c.kind) == "selfcare":
			bandage.append(c)
	check(bandage.size() == 1 and bool(bandage[0].ok), "E offers the bandage")
	var r: Dictionary = sim.interact.use(bandage[0])
	check(bool(r.ok), "she begins")
	Helpers.run(sim, float(r.seconds) + 0.5)
	check(float(me.bleeding) <= 0.0, "the wound is bandaged")
	eq(sim.inv.carried_totals().meds, pack_meds - 1, "one bandage out of the pack")
	near(float(sim.stock.meds), 5.0, 0.001, "and the stores' medicine is untouched")
	# no bandage in the pack, medicine in the stores, not at the base: refused
	sim.inv.deposit_all(true)
	me.bleeding = 1.0
	var ok_cands: Array = []
	for c in sim.interact.candidates():
		if String(c.kind) == "selfcare":
			ok_cands.append(c)
	check(ok_cands.size() == 1 and not bool(ok_cands[0].ok), "with an empty pack and away from the base the stores' medicine is out of reach")
	g.world.free()


func test_when_the_stores_are_short_she_eats_and_drinks_from_the_pack() -> void:
	# (PH10: the stores serve her only at the base; out in the town nothing is served, and what she eats is her own pack's, by hand: tests/test_needs.gd)
	var g := _claimed_pack_game()
	var sim = g.sim
	var me = _p(sim)
	sim.stock.food = 0.0
	sim.stock.water = 0.0
	var food0: int = sim.inv.carried_totals().food
	var water0: int = sim.inv.carried_totals().water
	me.hunger_h = 12.0
	me.thirst_h = 12.0
	check(sim.base.at_base(me), "she is at home")
	Helpers.run_to_hour(sim, 13.2)
	check(me.hunger_h < 12.0 and me.thirst_h < 12.0, "the noon meal fed her (hunger %.1f, thirst %.1f)" % [me.hunger_h, me.thirst_h])
	check(sim.inv.carried_totals().food < food0 and sim.inv.carried_totals().water < water0, "out of the pack")
	var c: Dictionary = sim.inv.carried_totals()
	check(food0 - int(c.food) <= 1 and water0 - int(c.water) <= 1, "a meal is a third of a ration and half a bottle: at most one unit gone (the rest is credit)")
	g.world.free()


func test_the_stash_deposits_and_withdraws_only_where_she_may() -> void:
	var g := _pack_game()
	var sim = g.sim
	check(sim.inv.deposit_all().is_empty(), "away from the stash and the base nothing is deposited")
	eq(sim.inv.withdraw("ammo", 5), 0, "and nothing is withdrawn")
	sim.inv.open_stash()
	check(sim.inv.stash_open and _events(sim, "stash_open").size() == 1, "E at the stash opens its panel (a flag and an event)")
	var carried: Dictionary = sim.inv.carried_totals()
	var stores_before: Dictionary = sim.inv.store_totals()
	var put: Dictionary = sim.inv.deposit_all()
	eq(int(put.get("ammo", 0)), int(carried.ammo), "all the shells deposited")
	var stores_after: Dictionary = sim.inv.store_totals()
	for r in ["ammo", "food", "water", "meds"]:
		eq(int(stores_after[r]) - int(stores_before[r]), int(carried[r]), "the stores gained what was carried: %s" % r)
	eq(sim.inv.carried_totals().ammo, 0, "and the pack has none")
	eq(sim.inv.withdraw("ammo", 12), 12, "twelve shells back")
	eq(sim.inv.carried_totals().ammo, 12, "in the pack")
	eq(int(sim.inv.store_totals().ammo), int(stores_after.ammo) - 12, "out of the stores")
	eq(sim.inv.withdraw("water", 7), 7, "seven water as items")
	eq(sim.inv.carried_totals().water, 7, "seven in the pack")
	check(sim.inv.stats.deposits == 1, "one trip to the stash counted")
	g.world.free()


func test_the_credit_goes_back_to_the_stores_with_the_deposit() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	me.mag = 0
	check(sim.inv.load_shots(me, 6) == 6, "six shots loaded")
	var credit: float = float(sim.inv.credit.ammo)
	check(credit > 0.9 and credit < 1.0, "a fraction of a shell is paid ahead: %.2f" % credit)
	var before: float = float(sim.stock.ammo)
	sim.inv.deposit_all(true)
	near(float(sim.stock.ammo) - before, float(37) + credit, 0.001, "37 shells and the fraction go to the stores")
	near(float(sim.inv.credit.ammo), 0.0, 0.0001, "and the credit is cleared")
	g.world.free()


func test_the_pack_is_saved_with_the_run() -> void:
	var g := _pack_game()
	var sim = g.sim
	var id := _go_to_a_container(sim)
	var r: Dictionary = sim.search.use(sim.search.candidates(_p(sim))[0])
	Helpers.run(sim, float(r.seconds) + 0.5)
	sim.inv.take_item(id, 0)
	sim.inv.drop(0, 1)
	var me = _p(sim)
	me.mag = 0
	sim.inv.load_shots(me, 3)
	sim.inv.give("water_jug", 1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	check(data.modules.has("inv") and bool(data.modules.inv.on), "the module is in the save")
	var f := Helpers.town_game(1, {"home": true})
	check(SaveGame.apply(f.sim, data), "the save is read")
	var inv2 = f.sim.inv
	check(inv2.on, "the pack is on after a load")
	eq(Inventory.to_dict(inv2.pack), Inventory.to_dict(sim.inv.pack), "the backpack is the same")
	eq(inv2.ground, sim.inv.ground, "so is what lies on the ground")
	eq(inv2.credit, sim.inv.credit, "and the credit")
	eq(inv2.searched, sim.inv.searched, "and which containers were searched")
	eq(f.sim.search.looted, sim.search.looted, "and the looted flags")
	for cid in sim.inv.containers:
		eq(Inventory.to_dict(inv2.containers[cid]), Inventory.to_dict(sim.inv.containers[cid]), "the container %s keeps its items" % String(cid))
	eq(f.sim.search.has_left(id), sim.search.has_left(id), "and what was left in it")
	eq(SaveGame.town_compat(data), "", "the town version in the save is this build's")
	check(int(TownGen.VERSION) >= 3, "the saved meaning changed: the town version was bumped")
	f.world.free()
	g.world.free()


func test_no_other_game_has_a_pack() -> void:
	# a bare town game (a test's stand-in, the title) never turns it on: the stores are what the avatar fires and eats
	var g := Helpers.town_game(1, {"home": true})
	var sim = g.sim
	check(not sim.inv.on and not sim.inv.active(), "no pack until a run begins with one")
	var me = _p(sim)
	sim.stock.ammo = 30.0
	eq(sim.reserve_ammo(me), 30.0, "her reserve is the stores'")
	near(sim.ammo_total(), 30.0, 0.001, "the total is the stores'")
	me.mag = 0
	sim.avatar.reload()
	Helpers.run(sim, 4.0)
	eq(int(me.mag), int(me.gun.mag), "she reloads from the stores: full")
	g.world.free()
	# the school-yard sim has no such part at all
	var school := Helpers.make(3, 1)
	check(school.sim.get("inv") == null, "the school's sim has no pack")
	near(school.sim.ammo_total(), float(school.sim.stock.ammo), 0.0001, "its totals are its stock")
	school.world.free()


# ------------------------------------------------------------------------- the base --

func _mid(d: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for t in d.tiles:
		sum += Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	return sum / float(d.tiles.size())


func _floor_near(sim, h: int, at: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for r in sim.houses.rooms_of(h):
		var rect: Rect2i = sim.houses.room(r).rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2(float(x) + 0.5, float(y) + 0.5)
				if c.distance_to(at) < best_d:
					best_d = c.distance_to(at)
					best = c
	return best


## The start house cleared (its dead put down), looked into, claimed; the pack on.
func _claimed_pack_game() -> Dictionary:
	var g := Helpers.town_game(1, {"home": true})
	var sim = g.sim
	sim.field.pause_wake = true
	var h: int = sim.houses.start_house()
	for d in sim.houses.doors_of(h):
		_at(sim, _mid(d))
		Helpers.run(sim, 0.3)
	var f = sim.field
	for r in sim.houses.rooms_of(h):
		for i in f.n:
			if f.status[i] == f.DORMANT and sim.houses.room_at(f.xs[i], f.ys[i]) == r:
				f.status[i] = f.KILLED
	_at(sim, _floor_near(sim, h, sim.base.claim_spot()))
	Helpers.run(sim, 0.3)
	check(bool(sim.base.claim(h).ok), "the start house is claimed")
	var start: Dictionary = OneHouse.data().start
	sim.inv.begin(start.pack)
	sim.events.clear()
	g["house"] = h
	return g


func test_at_the_stash_the_panel_opens_and_a_full_pack_is_reminded_at_the_door() -> void:
	var g := _claimed_pack_game()
	var sim = g.sim
	var me = _p(sim)
	check(sim.base.claimed and sim.base.at_base(me), "she is at the base")
	eq(sim.inv.bar_totals(), sim.inv.store_totals(), "after the claim the top bar shows the stores")
	# the stash: E offers it, uses it, the panel is open; walking away shuts it
	var stash: Dictionary = sim.base.prop("stash")
	_at(sim, Vector2(stash.pos))
	Helpers.run(sim, 0.2)
	var cs: Array = []
	for c in sim.interact.candidates():
		if String(c.kind) == "stash":
			cs.append(c)
	check(cs.size() == 1 and String(cs[0].label) == "Open the stash", "E offers the stash")
	check(bool(sim.interact.use(cs[0]).ok) and sim.inv.stash_open, "and opens its panel")
	_at(sim, Vector2(stash.pos) + Vector2(5.0, 0.0))
	Helpers.run(sim, 0.2)
	check(not sim.inv.stash_open, "walking away shuts the panel")
	# a full pack carried out of the base and back in: one reminder
	var pack: Dictionary = sim.inv.pack
	var more := true
	while more:
		more = false
		for it in ["water_jug", "water_bottle", "bandage", "canned_food", "shells"]:
			if Inventory.auto_add(pack, it, 1) == 0:
				more = true
	_at(sim, Vector2(sim.base.compound().position) + Vector2(-6.0, -6.0))
	Helpers.run(sim, 0.3)
	check(not sim.base.at_base(me), "she is outside the base")
	sim.alerts.erase("pack-home")
	_at(sim, Vector2(stash.pos))
	Helpers.run(sim, 0.3)
	check(sim.alerts.has("pack-home"), "walking home with a full pack tells her to use the stash")
	g.world.free()


# ------------------------------------------------------------- the prison doors --
## (prison_doors.gd is tested here for want of a prison test file: no new test files.) A stand-in game with just what the doors read: the world's solid tiles, the path grids, Ruth, the crew, the dead.

class _DoorPath:
	func set_solid(_k: int, _s: bool) -> void:
		pass


class _DoorWorld:
	var W := 67
	var solid_p := PackedByteArray()
	var solid_z := PackedByteArray()


class _DoorSim:
	var path_p
	var path_z
	var zombies: Array = []
	var _regions_dirty := false


class _DoorRun:
	var sim
	var avatar_p := {"x": 0.0, "y": 0.0}


class _DoorCrew:
	var members: Array = []


class _DoorGame:
	var world
	var run
	var crew
	var audio = null


func _door_game(clear: bool) -> Array:
	var Doors = load("res://scripts/prison/prison_doors.gd")
	var g := _DoorGame.new()
	g.world = _DoorWorld.new()
	g.world.solid_p.resize(67 * 70)
	g.world.solid_z.resize(67 * 70)
	g.run = _DoorRun.new()
	g.run.sim = _DoorSim.new()
	g.run.sim.path_p = _DoorPath.new()
	g.run.sim.path_z = _DoorPath.new()
	g.crew = _DoorCrew.new()
	var d = Doors.new()
	d.setup(g, clear)
	return [g, d]


func _door_tile(g, i: int) -> int:
	var Base = load("res://scripts/prison/prison_base.gd")
	var r: Rect2i = Base.doors()[i].rect
	return g.world.solid_p[r.position.y * 67 + r.position.x]


func test_a_prison_door_is_passable_from_the_start_of_opening_and_solid_only_at_the_end_of_shutting() -> void:
	var gd: Array = _door_game(true)
	var g = gd[0]
	var d = gd[1]
	g.run.avatar_p = {"x": 15.5, "y": 26.0}    # inside the infirmary, a step from its north door (door 1)
	eq(_door_tile(g, 1), 1, "the clear phase starts the door shut and solid")
	d.toggle(1)
	eq(_door_tile(g, 1), 0, "opening: passable on the first frame")
	d.tick(0.15)
	check(d._k(1) > 0.6, "eased out: well over half open half way through the swing (%s)" % d._k(1))
	d.tick(0.16)
	eq(d._k(1), 1.0, "open after 0.3 s")
	d.toggle(1)
	d.tick(0.15)
	eq(_door_tile(g, 1), 0, "shutting: still passable while the leaves swing")
	d.tick(0.16)
	eq(_door_tile(g, 1), 1, "solid once the swing has ended")
	# E during the swing turns it back from where it is, with no jump
	d.toggle(1)
	d.tick(0.1)
	var k: float = d._k(1)
	d.toggle(1)
	check(absf(d._k(1) - k) < 0.001, "a second E mid-swing turns it back smoothly (%s then %s)" % [k, d._k(1)])
	d.tick(0.31)
	eq(_door_tile(g, 1), 1, "and it ends shut")
	# nobody gets shut in: a crew member who steps into the doorway while it swings shut opens it again
	d.toggle(1)
	d.tick(0.31)
	d.toggle(1)
	g.crew.members = [{"p": {"x": 15.5, "y": 25.7, "moving": false}}]
	d.tick(0.31)
	eq(_door_tile(g, 1), 0, "a person within a tile of the doorway at the end of the swing: it swings open again")
	check(bool(d.open[1]), "and stays open")
	eq(d.toggle(1), "Something is in the doorway.", "E will not shut it on them")
	g.crew.members = []
	g.run.avatar_p = {"x": 15.5, "y": 24.5}
	eq(d.toggle(1), "Something is in the doorway.", "nor on Ruth standing in it")
	# the crew open a shut door as they walk up to it, but one who only stands by leaves it shut
	g.run.avatar_p = {"x": 15.5, "y": 27.0}
	d.toggle(1)
	d.tick(0.31)
	eq(_door_tile(g, 1), 1, "shut again")
	g.crew.members = [{"p": {"x": 15.5, "y": 23.0, "moving": false}}]
	d.tick(0.1)
	eq(_door_tile(g, 1), 1, "an ally standing a step outside does not open it")
	g.crew.members[0].p.moving = true
	d.tick(0.01)
	eq(_door_tile(g, 1), 0, "walking up to it, they open it")


func test_a_managed_base_door_opens_at_two_tiles_and_shuts_only_after_a_quiet_spell() -> void:
	var gd: Array = _door_game(false)
	var g = gd[0]
	var d = gd[1]
	g.run.avatar_p = {"x": 15.5, "y": 30.0}    # far from the infirmary's north door (door 1)
	for n in 30:
		d.tick(0.1)
	check(not bool(d.shown[1]), "nobody near: shut")
	g.run.avatar_p = {"x": 15.5, "y": 27.0}    # 2 tiles from the doorway
	d.tick(0.05)
	check(bool(d.shown[1]), "at 2 tiles it swings open")
	g.run.avatar_p = {"x": 15.5, "y": 27.6}    # 2.6 tiles: past the open radius, inside the shut one
	var flapped := false
	for n in 50:
		d.tick(0.1)
		flapped = flapped or not bool(d.shown[1])
	check(not flapped, "standing at the edge does not make it flap")
	g.run.avatar_p = {"x": 15.5, "y": 29.0}    # 4 tiles away
	d.tick(1.4)
	check(bool(d.shown[1]), "still open 1.4 s after they left")
	d.tick(0.2)
	check(not bool(d.shown[1]), "shut after 1.5 s of nobody within 3 tiles")


func test_every_prison_door_swings_into_its_building_and_no_leaf_crosses_a_wall_or_a_thing() -> void:
	var Base = load("res://scripts/prison/prison_base.gd")
	var Doors = load("res://scripts/prison/prison_doors.gd")
	for east in [false, true]:
		Base.east = east
		var b = Base.new()
		b.build(1, true)
		for dr in Base.doors():
			var r := Rect2(dr.rect)
			var n: Vector2 = Doors.side(r)
			var room: Vector2 = r.get_center() + n * 1.0
			check(b.solid[int(room.y) * Base.W + int(room.x)] == 0, "%s door %s: the side it swings to is floor" % [dr.name, dr.rect])
			for k in [0.25, 0.5, 0.75, 1.0]:
				for q in Doors.leaves(r, n, k, 11.0 / 64.0):
					var c: Vector2 = (q[0] + q[1] + q[2] + q[3]) / 4.0
					for v in q:
						var s: Vector2 = v + (c - v) * 0.1    # (a hair inside the leaf: its edge may touch a wall's face)
						for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
							var pt: Vector2 = s.lerp(c, f)
							var ti: int = int(pt.y) * Base.W + int(pt.x)
							check(b.solid[ti] == 0, "%s door %s (east %s): a leaf at %s crosses a wall or a solid thing at %s" % [dr.name, dr.rect, east, k, pt])
			for o in b.objects:
				var ob := Rect2(float(o.cx) - 0.4, float(o.cy) - 0.4, 0.8, 0.8)
				for k in [0.25, 0.5, 0.75, 1.0]:
					for q in Doors.leaves(r, n, k, 11.0 / 64.0):
						var c: Vector2 = (q[0] + q[1] + q[2] + q[3]) / 4.0
						check(not ob.has_point(c) and not ob.has_point((q[1] + q[2]) / 2.0), "%s door %s: a leaf at %s sweeps over the %s at %s,%s" % [dr.name, dr.rect, k, o.kind, o.cx, o.cy])
	Base.east = false
