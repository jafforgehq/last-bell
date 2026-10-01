## Audit evidence (2026-10-01): does the crew keep killing with 0 ammo?
## Runs one night from 19:00 with 300 ammo and with 0 and prints kills.
## Result at HEAD e4fa379: 32 kills both times (ammo is only a counter).
##   Godot --headless --path . --script docs/audit/evidence/ammo_check.gd
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")


func _initialize() -> void:
	for ammo in [300.0, 0.0]:
		var g := Helpers.make(11, 1)
		var sim = g.sim
		sim.stock.ammo = ammo
		sim.minutes = 19.0 * 60.0
		sim.phase = sim.phase_at(sim.minutes)
		sim.bell_rung = true
		Helpers.run(sim, 200.0)
		print("start ammo %.0f -> after one night: ammo %.1f, kills %d, alive walkers %d, people alive %d" % [ammo, sim.stock.ammo, sim.kills, sim.zombies.filter(func(z): return z.state != "dead" and z.state != "dying").size(), sim.people.filter(func(p): return not p.dead).size()])
		g.world.free()
	quit()
