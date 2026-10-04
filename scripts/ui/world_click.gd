## What a left click on the world means to the survivor's hands in "Right button aims" (round 22, scripts/aim_mode.gd). Pure geometry over
## what the rules say can be used (`sim.interact.candidates()`, which lists the things in reach, and `far_things()`, the same things
## wherever they are): which of those things a point of the world is on. The yard (scripts/main.gd) and a place (scripts/raid/raid_scene.gd)
## ask it for the click, the ring and the pill under the free pointer, and for the hand cursor.
extends RefCounted

## How far from the spot of a thing (tiles) a point still counts as on it, by kind; any other kind (the gate of round 22 among them) has
## DEFAULT_RADIUS.
const RADIUS := {"post": 1.0, "bench": 1.4, "vehicle": 2.2, "wall": 1.6, "gate": 1.8}
const DEFAULT_RADIUS := 1.3
## What the toast says of a thing that is out of reach.
const TOO_FAR := "Too far: walk closer"


## How far (tiles) a point may be from the spot of a thing of this kind and still be on it.
static func radius_of(kind: String) -> float:
	return float(RADIUS.get(kind, DEFAULT_RADIUS))


## The thing of `things` (the rules' shape: {"kind", "id", "pos", ...}) that the point `at` is on, the nearest to it when two are; {} for none. A
## person is never found here (the yard's own pick has people: their picture is taller than a spot). `ctx` may name what the picture says
## is under the point: {"seg": the wall section's id, "vehicle": the parked vehicle's id}; a wall or a vehicle that the picture has under the
## point is on it wherever its spot is.
static func under(at: Vector2, things: Array, ctx: Dictionary = {}) -> Dictionary:
	var best := {}
	var best_d := INF
	for t in things:
		var kind := String(t.get("kind", ""))
		if kind == "person":
			continue
		var pos: Vector2 = t.get("pos", Vector2.ZERO)
		var d := at.distance_to(pos)
		var hit := d <= radius_of(kind)
		if kind == "wall" and int(ctx.get("seg", -1)) >= 0 and int(ctx.get("seg", -1)) == int(t.get("seg", -2)):
			hit = true
		elif kind == "vehicle" and String(ctx.get("vehicle", "")) != "" and String(ctx.get("vehicle", "")) == String(t.get("id", "")):
			hit = true
		if hit and d < best_d:
			best = t
			best_d = d
	return best


## Whether `thing` is one of `cands` (the same kind and id): the thing a click is on is in reach when the rules list it.
static func listed(thing: Dictionary, cands: Array) -> Dictionary:
	for c in cands:
		if String(c.get("kind", "")) == String(thing.get("kind", "")) and String(c.get("id", "")) == String(thing.get("id", "")):
			return c
	return {}
