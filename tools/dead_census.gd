## A census of the town's dead as the generator places them (DEAD1): how many are in the houses, in the yards and in the streets, how many of the street's stand or wander, and how many lie in each
## band of distance from the entry, for a set of seeds. No play, no sim: only `TownGen.make`.
##
##   godot --headless --path . --script res://tools/dead_census.gd -- --seeds=1..6 [--blocks=6]
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
## The bands of distance from the entry (tiles) the street's dead are counted in.
const BANDS := [0.0, 24.0, 40.0, 60.0, 90.0, 140.0, 400.0]


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var seeds: Array = []
	var blocks := 6
	var dense := false
	for a in OS.get_cmdline_user_args():
		var t := String(a)
		if t.begins_with("--seeds="):
			var parts := t.trim_prefix("--seeds=").split("..")
			for s in range(int(parts[0]), int(parts[parts.size() - 1]) + 1):
				seeds.append(s)
		elif t.begins_with("--blocks="):
			blocks = int(t.trim_prefix("--blocks="))
		elif t == "--dense":
			dense = true
	if seeds.is_empty():
		seeds = [1]
	var sum := {"house": 0, "yard": 0, "street": 0, "street_still": 0, "street_wander": 0, "walker": 0, "runner": 0, "brute": 0}
	var band_sum: Array = []
	for b in BANDS.size() - 1:
		band_sum.append(0)
	var digest_sum := 0
	for s in seeds:
		var town: Dictionary = TownGen.make(int(s), {"blocks": blocks})
		var entry: Vector2 = Vector2(Arrival.spawn(town).pos) if town.has("start") else Vector2.ZERO
		var c := {"house": 0, "yard": 0, "street": 0, "street_still": 0, "street_wander": 0}
		var bands: Array = []
		for b in BANDS.size() - 1:
			bands.append(0)
		for d in town.dead:
			var hid := int(d.house)
			if hid >= 0 and int(d.get("room", -1)) >= 0:
				c.house += 1
			elif hid >= 0:
				c.yard += 1
			else:
				c.street += 1
				if String(d.state) == "still":
					c.street_still += 1
				else:
					c.street_wander += 1
				var dist := Vector2(d.pos).distance_to(entry)
				for b in BANDS.size() - 1:
					if dist >= BANDS[b] and dist < BANDS[b + 1]:
						bands[b] += 1
						break
			sum[String(d.kind)] += 1
		for k in c:
			sum[k] += int(c[k])
		for b in bands.size():
			band_sum[b] += int(bands[b])
		digest_sum = (digest_sum + TownGen.digest(town)) & 0xFFFFFFFF
		if dense:
			# the densest discs of the street's dead (8 tiles across) for a picture: where the avatar should stand, `--avatar-at=x,y`
			var best: Array = []
			for a in town.dead:
				if int(a.house) >= 0:
					continue
				var n8 := 0
				for b in town.dead:
					if int(b.house) < 0 and Vector2(a.pos).distance_to(Vector2(b.pos)) < 8.0:
						n8 += 1
				best.append([n8, Vector2(a.pos), Vector2(a.pos).distance_to(entry)])
			best.sort_custom(func(x, y): return x[0] > y[0])
			var shown := 0
			for e in best:
				if shown >= 4:
					break
				print("   dense: %d street dead within 8 tiles of %.1f,%.1f (%.0f tiles from the entry)" % [e[0], e[1].x, e[1].y, e[2]])
				shown += 1
		print("seed %2d: dead %4d (houses %3d, yards %3d, streets %3d: %3d still %3d wander)  street bands %s" % [s, town.dead.size(), c.house, c.yard, c.street, c.street_still, c.street_wander, str(bands)])
	var n := float(seeds.size())
	print("MEAN over %d seeds: houses %.0f, yards %.0f, streets %.0f (%.0f still, %.0f wander); kinds walker %.0f runner %.0f brute %.0f" % [seeds.size(), sum.house / n, sum.yard / n, sum.street / n, sum.street_still / n, sum.street_wander / n, sum.walker / n, sum.runner / n, sum.brute / n])
	var means: Array = []
	for b in band_sum.size():
		means.append(snappedf(float(band_sum[b]) / n, 0.1))
	print("street dead by distance from the entry (%s tiles): %s   digest sum %d" % [str(BANDS), str(means), digest_sum])
	quit()
