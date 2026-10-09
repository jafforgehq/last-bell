## The reachability probe of WORLD3: for each seed, a flood fill on the avatar's walking grid (`sim.world.solid_p`) from the arrival's entry, and then, for EVERY house of the town (not only the
## candidates): is every room, every container, every rescue spot and every dead one's place reachable? Prints one line a seed and the unreachable ones by kind of building. The same flood as
## the QA2 probe (probe_reach.gd), widened to the whole town.
##
##   godot --headless --path . --script res://tools/probe_world.gd -- --seeds=1..16
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const Arrival := preload("res://scripts/town/arrival.gd")


func _initialize() -> void:
	_main.call_deferred()


static func flood(sim, from: Vector2) -> PackedByteArray:
	var w: int = int(sim.W)
	var h: int = int(sim.H)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var sp = sim.world.solid_p
	var start := Vector2i(floori(from.x), floori(from.y))
	var q: Array = [start]
	seen[start.y * w + start.x] = 1
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var i: int = n.y * w + n.x
			if seen[i] == 1 or int(sp[i]) != 0:
				continue
			seen[i] = 1
			q.append(n)
	return seen


static func near_reach(sim, seen: PackedByteArray, at: Vector2, r: int) -> bool:
	var w: int = int(sim.W)
	var cx := floori(at.x)
	var cy := floori(at.y)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= w or y >= int(sim.H):
				continue
			if seen[y * w + x] == 1:
				return true
	return false


func _main() -> void:
	var seeds: Array = []
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--seeds="):
			var parts := String(a).trim_prefix("--seeds=").split("..")
			for s in range(int(parts[0]), int(parts[parts.size() - 1]) + 1):
				seeds.append(s)
	if seeds.is_empty():
		seeds = [1]
	var total_bad := 0
	for sd in seeds:
		var g := Helpers.town_game(int(sd), {"blocks": 6})
		var sim = g.sim
		var town: Dictionary = g.town
		var spawn = Arrival.spawn(town)
		var seen := flood(sim, spawn.pos)
		var hs = sim.houses
		var rooms_n := 0
		var rooms_bad := 0
		var cont_n := 0
		var cont_bad := 0
		var bad_by_kind := {}
		var kinds := {}
		for h in town.houses:
			var hid := int(h.id)
			kinds[String(h.kind)] = true
			for r in hs.rooms_of(hid):
				rooms_n += 1
				var rect := Rect2i(hs.room(int(r)).rect)
				var any := false
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						if seen[y * int(sim.W) + x] == 1:
							any = true
				if not any:
					rooms_bad += 1
					bad_by_kind[String(h.kind)] = int(bad_by_kind.get(String(h.kind), 0)) + 1
			for k in hs.containers_of(hid):
				cont_n += 1
				if not near_reach(sim, seen, Vector2(k.pos), 1):
					cont_bad += 1
					bad_by_kind["cont:" + String(h.kind)] = int(bad_by_kind.get("cont:" + String(h.kind), 0)) + 1
		var field = sim.field
		var dead_n := int(field.n)
		var dead_bad := 0
		for i in dead_n:
			if not near_reach(sim, seen, Vector2(field.xs[i], field.ys[i]), 1):
				dead_bad += 1
		var resc_n := 0
		var resc_bad := 0
		for c in Arrival.candidates(town):
			for r in Arrival.rescue_for(town, int(c.house)):
				resc_n += 1
				if not near_reach(sim, seen, Vector2(r.pos), 1):
					resc_bad += 1
		total_bad += rooms_bad + cont_bad + resc_bad
		print("seed %d: houses %d kinds %d | rooms %d (unreached %d) containers %d (unreached %d) dead %d (unreached %d) rescue spots %d (unreached %d) %s" % [int(sd), town.houses.size(), kinds.size(), rooms_n, rooms_bad, cont_n, cont_bad, dead_n, dead_bad, resc_n, resc_bad, JSON.stringify(bad_by_kind)])
		g.world.free()
	print("PROBE_WORLD seeds %d, unreached rooms+containers+rescue spots: %d" % [seeds.size(), total_bad])
	quit(0)
