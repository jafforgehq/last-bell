## Audit evidence (2026-10-01): the school-keep exploit.
## "keep" sends all six into the school gym on day 1 and gives no other order;
## "default" leaves them at their posts. Prints alive/hurt/walls/food/ammo at days 5, 10, 15, 20.
## Result at HEAD e4fa379 (seeds 1-3): keep = 6 alive and 0 hurt on day 20; default dies by about day 13.
##   Godot --headless --path . --script docs/audit/evidence/keep_check.gd   (slow: several minutes)
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")


func _alive(sim) -> int:
	var n := 0
	for p in sim.people:
		if not p.dead:
			n += 1
	return n


func _in_yard(sim) -> int:
	var n := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying" and z.x > 20.0 and z.x < 64.0 and z.y > 18.0 and z.y < 47.0:
			n += 1
	return n


func _wall_pct(sim) -> float:
	var hp := 0.0
	var mx := 0.0
	for s in sim.segments:
		hp += s.hp
		mx += s.max_hp
	return 100.0 * hp / maxf(mx, 1.0)


func _initialize() -> void:
	for mode in ["keep", "default"]:
		for seed_value in [1, 2, 3]:
			var g := Helpers.make(seed_value, 1)
			var sim = g.sim
			sim.waves.enabled = true
			var wounds := 0
			if mode == "keep":
				var i := 0
				for p in sim.people:
					sim.order_move(p, 28.5 + float(i) * 2.2, 51.5)
					i += 1
			var line := "%-7s seed %d: " % [mode, seed_value]
			for day in range(1, 21):
				Helpers.run(sim, 480.0)
				if sim.over != "":
					line += "| over on day %d (%s) " % [day, sim.over]
					break
				if day in [5, 10, 15, 20]:
					var hurt := 0
					for p in sim.people:
						if not p.dead and (p.bleeding or p.wounds > 0):
							hurt += 1
					line += "| d%d alive %d hurt %d inYard %d walls %.0f%% food %.0f ammo %.0f " % [day, _alive(sim), hurt, _in_yard(sim), _wall_pct(sim), sim.stock.food, sim.stock.ammo]
			print(line)
			g.world.free()
	quit()
