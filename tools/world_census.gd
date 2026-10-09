## A census of the town's buildings (WORLD3): how many kinds and plans of each category a set of seeds makes, and how many DISTINCT BUILDING SIGNATURES a town has (footprint + roof + colour).
##
##   godot --headless --path . --script res://tools/world_census.gd -- --seeds=1..6 [--out=/tmp/census.json]
##
## A footprint is the list of the parts' rectangles relative to the box, the front turned to the north, a mirrored one counted as the same (so an L and its mirror are one). The OLD signature is
## kind + footprint + roof kit + wall material (what a town had before WORLD3); the NEW one adds the roof shape and colour and the facade's features (`house.facade`, when there is one).
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const Plans := preload("res://scripts/town/building_plans.gd")

const Recipes := preload("res://scripts/town/building_recipes.gd")
## The category of a kind of building (the old kinds and the new ones: scripts/town/building_recipes.gd).
const CATEGORY := Recipes.CATEGORY


func _initialize() -> void:
	_main.call_deferred()


func _footprint(h: Dictionary) -> String:
	var box: Rect2i = h.rect
	var parts: Array = []
	for pr in h.parts:
		var r: Rect2i = pr
		var y := r.position.y - box.position.y
		if String(h.front) == "S":
			y = box.size.y - y - r.size.y
		parts.append(Vector4i(r.position.x - box.position.x, y, r.size.x, r.size.y))
	var a := _fp_string(parts, box.size.x, false)
	var b := _fp_string(parts, box.size.x, true)
	return a if a < b else b


func _fp_string(parts: Array, bw: int, mirror: bool) -> String:
	var items: Array = []
	for p in parts:
		var v: Vector4i = p
		var x := bw - v.x - v.z if mirror else v.x
		items.append("%d,%d,%dx%d" % [x, v.y, v.z, v.w])
	items.sort()
	return "|".join(items)


func _main() -> void:
	var seeds: Array = []
	var out := ""
	for a in OS.get_cmdline_user_args():
		var t := String(a)
		if t.begins_with("--seeds="):
			var parts := t.trim_prefix("--seeds=").split("..")
			for s in range(int(parts[0]), int(parts[parts.size() - 1]) + 1):
				seeds.append(s)
		elif t.begins_with("--out="):
			out = t.trim_prefix("--out=")
	if seeds.is_empty():
		seeds = [1]
	var kinds := {}
	var vars := {}
	var cats := {}
	var plan_cat := {}
	var footprints := {}
	var roofs := {}
	var walls := {}
	var feat := {}
	var per_town_old: Array = []
	var per_town_new: Array = []
	var per_town_fp: Array = []
	var per_town_plans: Array = []
	var per_town_looks: Array = []
	var buildings := 0
	var ms_total := 0.0
	for sd in seeds:
		var t0 := Time.get_ticks_usec()
		var town: Dictionary = TownGen.make(int(sd), {"blocks": 6})
		ms_total += float(Time.get_ticks_usec() - t0) / 1000.0
		var old_sigs := {}
		var new_sigs := {}
		var fps := {}
		var pids := {}
		var looks := {}
		for h in town.houses:
			if not bool(h.main):
				continue
			buildings += 1
			var kind := String(h.kind)
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			var plan_id := String(h.get("var", kind))
			vars[plan_id] = int(vars.get(plan_id, 0)) + 1
			var cat := String(CATEGORY.get(kind, h.type))
			plan_cat[plan_id] = cat
			cats[cat] = int(cats.get(cat, 0)) + 1
			pids[plan_id] = true
			var fp := _footprint(h)
			footprints[fp] = true
			fps[fp] = true
			var fac: Dictionary = h.get("facade", {})
			var roof_key := "%s|%s|%s|%s" % [str(h.roof), String(fac.get("style", "gable")), str(fac.get("tint", "")), String(h.wall)]
			roofs["%s|%s|%s" % [str(h.roof), String(fac.get("style", "gable")), str(fac.get("tint", ""))]] = true
			walls[String(h.wall)] = true
			var old_sig := "%s|%s|%d|%s" % [kind, fp, int(h.roof), String(h.wall)]
			old_sigs[old_sig] = true
			looks["%s|%d|%s|%s|%s" % [plan_id, int(h.roof), String(fac.get("style", "gable")), str(fac.get("tint", "")), String(h.wall)]] = true
			new_sigs[old_sig + "|" + roof_key + "|" + JSON.stringify(fac.get("features", []))] = true
			for f in fac.get("features", []):
				feat[String(f)] = int(feat.get(String(f), 0)) + 1
			if String(h.state) != "intact":
				feat["state_" + String(h.state)] = int(feat.get("state_" + String(h.state), 0)) + 1
			if bool(h.boarded):
				feat["boarded"] = int(feat.get("boarded", 0)) + 1
			if int(Rect2i(h.drive).get_area()) > 0:
				feat["driveway"] = int(feat.get("driveway", 0)) + 1
		per_town_old.append(old_sigs.size())
		per_town_new.append(new_sigs.size())
		per_town_fp.append(fps.size())
		per_town_plans.append(pids.size())
		per_town_looks.append(looks.size())
	var cat_kinds := {}
	for k in kinds:
		var c := String(CATEGORY.get(k, "other"))
		cat_kinds[c] = int(cat_kinds.get(c, 0)) + 1
	var cat_vars := {}
	for pid in plan_cat:
		var c2 := String(plan_cat[pid])
		cat_vars[c2] = int(cat_vars.get(c2, 0)) + 1
	var res := {
		"seeds": seeds.size(), "buildings": buildings, "kinds_seen": kinds.size(), "plans_seen": vars.size(), "distinct_footprints": footprints.size(),
		"distinct_roof_looks": roofs.size(), "wall_materials": walls.size(),
		"avg_sigs_old": float(_sum(per_town_old)) / float(seeds.size()), "avg_sigs_new": float(_sum(per_town_new)) / float(seeds.size()), "avg_footprints_per_town": float(_sum(per_town_fp)) / float(seeds.size()), "avg_plans_per_town": float(_sum(per_town_plans)) / float(seeds.size()), "avg_looks_per_town": float(_sum(per_town_looks)) / float(seeds.size()),
		"per_town_sigs_new": per_town_new, "per_town_sigs_old": per_town_old,
		"buildings_by_category": cats, "kinds_by_category": cat_kinds, "plans_by_category": cat_vars, "features": feat, "gen_ms_avg": ms_total / float(seeds.size()),
	}
	print("CENSUS ", JSON.stringify(res, "  "))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	quit(0)


func _sum(a: Array) -> int:
	var s := 0
	for v in a:
		s += int(v)
	return s
