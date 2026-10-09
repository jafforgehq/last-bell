## The town probe (CLEAR3): for each seed the whole town and its arrival are made and checked, headless. A town has to be valid for EVERY seed, because a new game's seed is its town's.
##
##   godot --headless --path <project> --script res://tools/town_probe.gd -- --seeds=1..64 [--list=0,-5,482913] [--twice]
##
## Per seed: three validated candidates (best, ok, poor; `TownGen` drops one with a problem of the base's rules, `BaseLayout.validate`) with the door's distance from the entry in range (best 22 to 30,
## ok 17 to 32, poor 40 to 56) and the house's middle 36 tiles or more from the map's edge (the base's spawn rule); every candidate's rooms, outside doors, containers, dead and rescue spots are
## reachable from the entry (a 4-way flood of `data.solidP`), it has at least one container, at least two rescue spots are within a 120 tile walk of its door and at least eight are in its list; the
## town has 60 houses or more; the field of fire of each candidate (its lot grown by 10 tiles, scripts/town/town_fields.gd) has no other building and no tall solid tile; the time to make it (a budget
## of 5 s here: a busy machine is slow, and the numbers printed are the ones to read). `--twice` makes every town twice and compares `TownGen.digest`: the same seed is the same town.
## Prints one line a seed (`ok` or `FAIL` with the reasons: after `!!`) and a SUMMARY line.
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const Fields := preload("res://scripts/town/town_fields.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const BaseLayout := preload("res://scripts/town/base_layout.gd")

const RANGE := {"best": [22.0, 30.0], "ok": [17.0, 32.0], "poor": [40.0, 56.0]}
const MIN_HOUSES := 60
const BUDGET_MS := 5000.0
const WALK_REACH := 120


func _initialize() -> void:
	_main.call_deferred()


static func parse_seeds(args: Array) -> Array:
	var seeds: Array = []
	for a in args:
		var s := String(a)
		if s.begins_with("--seeds="):
			var parts := s.trim_prefix("--seeds=").split("..")
			if parts.size() == 2:
				for v in range(int(parts[0]), int(parts[1]) + 1):
					seeds.append(v)
		elif s.begins_with("--list="):
			for p in s.trim_prefix("--list=").split(","):
				seeds.append(int(p))
	return seeds


func _main() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := parse_seeds(args)
	if seeds.is_empty():
		seeds = [1]
	var twice := args.has("--twice")
	var fails := 0
	var max_ms := 0.0
	var sum_ms := 0.0
	var dmin := {"best": 999.0, "ok": 999.0, "poor": 999.0}
	var dmax := {"best": 0.0, "ok": 0.0, "poor": 0.0}
	var min_rescue_near := 999
	var min_houses := 999
	for sd in seeds:
		var t0 := Time.get_ticks_usec()
		var town: Dictionary = TownGen.make(int(sd), {"blocks": 6})
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		max_ms = maxf(max_ms, ms)
		sum_ms += ms
		var bad: Array = []
		if twice:
			var again: Dictionary = TownGen.make(int(sd), {"blocks": 6})
			if TownGen.digest(again) != TownGen.digest(town):
				bad.append("NOT DETERMINISTIC (digest differs)")
		if ms > BUDGET_MS:
			bad.append("slow %.0f ms" % ms)
		var nh: int = (town.houses as Array).size()
		min_houses = mini(min_houses, nh)
		if nh < MIN_HOUSES:
			bad.append("only %d houses" % nh)
		var cands: Array = town.candidates
		var tiers: Array = []
		for c in cands:
			tiers.append(String(c.tier))
		if tiers != ["best", "ok", "poor"]:
			bad.append("candidates %s (dropped %s)" % [str(tiers), JSON.stringify(town.stats.arrival.dropped)])
		var spawn: Dictionary = Arrival.spawn(town)
		var W: int = int(town.data.W)
		var sp = town.data.solidP
		var seen := flood(sp, W, spawn.pos)
		var parts: Array = []
		for c in cands:
			var hid := int(c.house)
			var h: Dictionary = town.houses[hid]
			var tier := String(c.tier)
			var d := float(c.dist)
			if RANGE.has(tier):
				dmin[tier] = minf(float(dmin[tier]), d)
				dmax[tier] = maxf(float(dmax[tier]), d)
				if d < float(RANGE[tier][0]) or d > float(RANGE[tier][1]):
					bad.append("%s dist %.1f out of %s" % [tier, d, str(RANGE[tier])])
			var ctr := Vector2(Rect2i(h.rect).get_center())
			var edge := minf(minf(ctr.x, ctr.y), minf(float(W) - ctr.x, float(W) - ctr.y))
			if edge < 36.0:
				bad.append("%s house centre %.0f tiles from the edge" % [tier, edge])
			if not (c.problems as Array).is_empty():
				bad.append("%s problems %s" % [tier, str(c.problems)])
			var lay: Dictionary = BaseLayout.make(town, hid)
			var vp: Array = BaseLayout.validate(lay, town)
			if not vp.is_empty():
				bad.append("%s validate %s" % [tier, str(vp)])
			var bad_rooms := 0
			for r in h.rooms:
				var rr := Rect2i(town.rooms[int(r)].rect)
				var any := false
				for y in range(rr.position.y, rr.end.y):
					for x in range(rr.position.x, rr.end.x):
						if seen[y * W + x] == 1:
							any = true
				if not any:
					bad_rooms += 1
			var bad_doors := 0
			for dr in h.doors:
				if bool(dr.exterior):
					var o: Vector2i = dr.out
					if seen[o.y * W + o.x] != 1:
						bad_doors += 1
			var bad_cont := 0
			if (h.containers as Array).is_empty():
				bad.append("%s has no container at all" % tier)
			for k in town.containers:
				if int(k.house) == hid and not near(seen, W, Vector2(k.pos), 1):
					bad_cont += 1
			var bad_dead := 0
			for di in h.dead:
				var rec: Dictionary = town.dead[int(di)]
				if not near(seen, W, Vector2(rec.pos), 1):
					bad_dead += 1
			var rs: Array = Arrival.rescue_for(town, hid)
			var bad_rs := 0
			for r in rs:
				if not near(seen, W, Vector2(r.pos), 1):
					bad_rs += 1
			# walking distances from the candidate's door
			var from: Vector2 = c.door
			var dist := bfs(sp, W, from)
			var near_rs := 0
			var first_walk := 9999
			for r in rs:
				var p: Vector2 = r.pos
				var best_d := 9999
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var v: int = dist[(floori(p.y) + dy) * W + floori(p.x) + dx]
						if v >= 0:
							best_d = mini(best_d, v)
				first_walk = mini(first_walk, best_d)
				if best_d <= WALK_REACH:
					near_rs += 1
			min_rescue_near = mini(min_rescue_near, near_rs)
			if bad_rooms > 0 or bad_doors > 0 or bad_cont > 0 or bad_dead > 0 or bad_rs > 0:
				bad.append("%s unreachable: rooms %d doors %d containers %d dead %d rescue %d" % [tier, bad_rooms, bad_doors, bad_cont, bad_dead, bad_rs])
			if near_rs < 2:
				bad.append("%s only %d rescue spots within a %d tile walk" % [tier, near_rs, WALK_REACH])
			if rs.size() < 8:
				bad.append("%s has only %d rescue spots" % [tier, rs.size()])
			var rep := Fields.report(town, hid, 10)
			if not (rep.buildings as Array).is_empty() or int(rep.tall) > 0:
				bad.append("%s field not clear: %d buildings, %d tall tiles" % [tier, (rep.buildings as Array).size(), int(rep.tall)])
			parts.append("%s d%.0f r%d c%d walk%d" % [tier, d, (h.rooms as Array).size(), (h.containers as Array).size(), first_walk])
		var verdict := "ok" if bad.is_empty() else "FAIL"
		if not bad.is_empty():
			fails += 1
		print("seed %d %s (%.0f ms, %d houses) %s%s" % [int(sd), verdict, ms, nh, " | ".join(parts), "" if bad.is_empty() else "  !! " + " ;; ".join(bad)])
	print("SUMMARY seeds %d, failed %d, ms mean %.0f max %.0f, houses min %d, dist best %.1f..%.1f ok %.1f..%.1f poor %.1f..%.1f, fewest rescue spots in a %d tile walk %d" % [
		seeds.size(), fails, sum_ms / float(seeds.size()), max_ms, min_houses, float(dmin.best), float(dmax.best), float(dmin.ok), float(dmax.ok), float(dmin.poor), float(dmax.poor), WALK_REACH, min_rescue_near])
	quit(0)


## The tiles a person can walk to from `from` (a 4-way flood of the solid grid `sp`, w x w).
static func flood(sp, w: int, from: Vector2) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * w)
	var q: Array = [Vector2i(floori(from.x), floori(from.y))]
	seen[q[0].y * w + q[0].x] = 1
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= w:
				continue
			var i: int = n.y * w + n.x
			if seen[i] == 1 or int(sp[i]) != 0:
				continue
			seen[i] = 1
			q.append(n)
	return seen


## The walking distance in tiles from `from` to every tile within 160 steps, -1 beyond.
static func bfs(sp, w: int, from: Vector2) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * w)
	dist.fill(-1)
	var q: Array = [Vector2i(floori(from.x), floori(from.y))]
	dist[q[0].y * w + q[0].x] = 0
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		var nd: int = dist[c.y * w + c.x] + 1
		if nd > 160:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= w:
				continue
			var i: int = n.y * w + n.x
			if dist[i] != -1 or int(sp[i]) != 0:
				continue
			dist[i] = nd
			q.append(n)
	return dist


static func near(seen: PackedByteArray, w: int, at: Vector2, r: int) -> bool:
	var cx := floori(at.x)
	var cy := floori(at.y)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= w or y >= w:
				continue
			if seen[y * w + x] == 1:
				return true
	return false
