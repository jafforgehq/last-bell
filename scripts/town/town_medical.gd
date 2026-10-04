## The colony's medical module for a town (feature/town-core): the one thing it asks of the school that a town does not have is the gate (`segments[2]`, medical.gd `_gate`,
## which `update` calls every step, to walk the infected out of it). In a town the gate is the base's, once there is one, else the front door of the start house.
## (Found by WP1 while running `Sim.update` on a town map; not in the plan's list of school assumptions, 1.5. A hook in medical.gd would have been the other way.)
extends "res://scripts/sim/medical.gd"


func _gate() -> Vector2:
	for s in sim.segments:
		if s.kind == "gate":
			var c: Vector2 = s.center
			return c
	var b = sim.get("base")
	if b != null and b.has_method("center"):
		return b.center()
	var town: Dictionary = sim.get("town_data") if sim.get("town_data") != null else {}
	if town.has("start"):
		var h: Dictionary = town.houses[int(town.start.house)]
		return Vector2(float(h.door.x) + 0.5, float(h.door.y) + 0.5)
	return Vector2.ZERO
