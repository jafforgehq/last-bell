## The rules of a played trip (round 14): the colony's own Sim, built on the map of a place (a site made by
## site_gen.gd) with the squad as its people and the dead of the place. Nothing of the colony runs (no hunger, no
## jobs, no radio): `RaidRun` steps only the people and the dead. It overrides the seeding of a new run, which the
## real map's wall sections would otherwise provide, and (round 17) what the hour changes: `mirror(colony)` gives it the
## colony's clock while the player is in the place (the base goes on meanwhile), the dead hunt at every hour and there
## are no wall posts to man, so a place can be played at night. With a player in the place the squad's stances (follow, hold,
## cover, search, back) are asked of `squad_goal`, the run's SquadAI (scripts/raid/squad_ai.gd), before the colony's own
## goals (`_goal_for`).
extends "res://scripts/sim/sim.gd"


## A place has no rally, no plated brutes and no hot breaches (round 19: `Sim.nights_on`).
func _init(data: Dictionary, w, effects) -> void:
	super(data, w, effects)
	nights_on = false


## The yard's own dead and the walls' slots do not exist in a site.
func _seed() -> void:
	pass


## A site has no yard.
func _in_yard(_x: float, _y: float) -> bool:
	return false


## The colony's clock, as the place keeps it while the player is in it (round 17): the scene calls this every frame (or
## step) with the colony's Sim, so that a place has the colony's day, hour, phase and bell, and can be played at night.
## `hour` follows from `minutes`.
func mirror(colony) -> void:
	day = int(colony.day)
	minutes = float(colony.minutes)
	clock_min = float(colony.clock_min)
	phase = String(colony.phase)
	bell_rung = bool(colony.bell_rung)


## The dead of a place hunt at every hour (the yard's stragglers give up at nightfall, `Sim._hunt_allowed`).
func _hunt_allowed() -> bool:
	return true


## A place has no wall posts to man, whatever the hour: the squad stands where it is told (a night in a place does not
## send them to the yard's posts).
func posts_manned() -> bool:
	return false


## What the squad's AI says a person should do now (`SquadAI.goal_for`, set by the run, round 17): {"x", "y", "face", "what"} or
## null (no stance, no player, or an order stands: then the colony's own rules decide, as before). A person with an order is
## left to the order.
var squad_goal: Callable


func _goal_for(p: Person):
	if squad_goal.is_valid() and p.order == null and not p.player and not p.downed and not p.dead:
		var asked = squad_goal.call(p)
		if asked != null:
			return asked
	return super(p)


## The squad shoots what it can see: a clear line to the target (the dead behind a wall are not shot).
func _find_target(p: Person):
	var reach: float = reach_of(gun_of(p), p)
	var best = null
	var best_score := INF
	for z in zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dist := Vector2(z.x - p.x, z.y - p.y).length()
		if dist > reach:
			continue
		if not path_z.sight(world.solid_z, Vector2(p.x, p.y), Vector2(z.x, z.y), 0.12):
			continue
		var score := dist - (3.0 if z.state == "hunt" and dist < 2.0 else 0.0) + float(Kinds.PRIORITY.get(z.kind, 0.0))
		if score < best_score:
			best_score = score
			best = z
	return best
