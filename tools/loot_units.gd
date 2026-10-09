## The loot-units table of INV-CORE: for each seed the town's containers (the houses' and the street's cars) as they were (the generator's `loot` {resource: units}, which is what a search used to add to
## the stores) and as they are now (the units of the ITEMS in the container's grid, plus the scrap that goes straight to the stores), per house and per town. They must match within 3 percent
## (they match exactly by construction: the items are made from the loot's units; this proves it, and that every container's items fit its grid without growing it).
##
##   Godot --headless --path . --script res://tools/loot_units.gd -- --seeds=1..16 [--blocks=6]
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const CarLoot := preload("res://scripts/town/car_loot.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")


func _initialize() -> void:
	_main.call_deferred()


static func _seeds(arg: String) -> Array:
	var out: Array = []
	var parts := arg.split("..")
	if parts.size() == 2:
		for v in range(int(parts[0]), int(parts[1]) + 1):
			out.append(v)
	elif arg != "":
		out.append(int(arg))
	return out


## {"before": units, "after": units, "grown": rows added, "n": containers, "cells": cells used, "worst": most cells in one container}.
static func tally(containers: Array, seed_value: int) -> Dictionary:
	var out := {"before": 0, "after": 0, "grown": 0, "n": 0, "cells": 0, "worst": 0, "by_res": {}}
	for c in containers:
		var loot: Dictionary = c.loot
		var before := 0
		for k in loot:
			before += int(loot[k])
		var grid := Inventory.make_container(String(c.kind), loot, seed_value * 31 + String(c.id).hash())
		var after := 0
		for r in ["ammo", "food", "water", "meds"]:
			var u := Inventory.units(grid, r)
			after += u
			out.by_res[r] = int(out.by_res.get(r, 0)) + u
		var loose := Inventory.loose_units(loot)
		for k in loose:
			after += int(loose[k])
			out.by_res[k] = int(out.by_res.get(k, 0)) + int(loose[k])
		out.before += before
		out.after += after
		out.grown += int(grid.get("grown", 0))
		if int(grid.get("grown", 0)) > 0:
			print("    grown: %s %s %s -> %dx%d" % [String(c.id), String(c.kind), str(loot), int(grid.w), int(grid.h)])
		out.n += 1
		var used := Inventory.used_cells(grid)
		out.cells += used
		out.worst = maxi(int(out.worst), used)
	return out


func _main() -> void:
	var seeds: Array = [1]
	var blocks := 6
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--seeds="):
			seeds = _seeds(s.trim_prefix("--seeds="))
		elif s.begins_with("--blocks="):
			blocks = int(s.trim_prefix("--blocks="))
	print("seed | containers | houses | units/house before | after | units/town before | after | diff %% | rows grown | cells/container | worst")
	var sum_b := 0
	var sum_a := 0
	var worst_diff := 0.0
	var grown := 0
	for sd in seeds:
		var town: Dictionary = TownGen.make(int(sd), {"blocks": blocks})
		var houses_with := {}
		for c in town.containers:
			houses_with[int(c.house)] = true
		var t_houses: Dictionary = tally(town.containers, int(sd))
		var cars: Array = CarLoot.containers(town)
		var t_cars: Dictionary = tally(cars, int(sd))
		var nh := maxi(houses_with.size(), 1)
		var before: int = int(t_houses.before) + int(t_cars.before)
		var after: int = int(t_houses.after) + int(t_cars.after)
		var diff := 100.0 * float(after - before) / maxf(float(before), 1.0)
		worst_diff = maxf(worst_diff, absf(diff))
		grown += int(t_houses.grown) + int(t_cars.grown)
		sum_b += before
		sum_a += after
		print("%4d | %4d + %3d cars | %3d | %6.2f | %6.2f | %5d | %5d | %+5.2f | %d | %.1f | %d" % [int(sd), int(t_houses.n), int(t_cars.n), nh, float(t_houses.before) / float(nh), float(t_houses.after) / float(nh), before, after, diff, int(t_houses.grown) + int(t_cars.grown), float(int(t_houses.cells) + int(t_cars.cells)) / float(maxi(int(t_houses.n) + int(t_cars.n), 1)), maxi(int(t_houses.worst), int(t_cars.worst))])
	print("TOTAL over %d seeds: before %d, after %d (%+.2f%%), worst seed diff %.2f%%, container rows grown %d | %s" % [seeds.size(), sum_b, sum_a, 100.0 * float(sum_a - sum_b) / maxf(float(sum_b), 1.0), worst_diff, grown, "within 3 percent" if worst_diff <= 3.0 else "OUT OF 3 PERCENT"])
	quit()
