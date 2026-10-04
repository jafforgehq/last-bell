## The rules of the One House town, the colony's Sim with the school taken out (the plan's section 1.1). `TownSim` (the dead of the street, the
## field, the loop) extends this and `Sim` is not edited for the town beyond the neutral hooks (`is_one_house`, `base_center`, `yard_middle`,
## `_wanderers_rally`, `_any_gate_open`, `_is_open_gate`, `alive_for_cap`: sim.gd): here they answer for a base that is a claimed house.
##
## Everything here asks the town's modules through `get("name")` and null checks, so the class works before any of them exists and in a test
## without them: `base` (scripts/town/base.gd: `claimed`, `house`, `center()`, `compound()`, `yard_rect()`, `yard_middle()`), `perimeter`
## (scripts/town/perimeter.gd: `no_outer_wall()`, `gate_open()`, `prepare_load`, `restore`), `scenario` (the scenario: `attacks_on()`), `houses`
## (`house_at(x, y)`) and `field` (the dormant dead: `rec_of`, a dead one that has a record is one of the town's own, not the night's).
##
## It does not declare those variables: `TownSim` does (its PARTS table), and a class that declared one twice would not load.
extends "res://scripts/sim/sim.gd"


func _init(data: Dictionary, w, effects) -> void:
	super(data, w, effects)
	_school_inner.clear()    # (there is no school inside the walls of a town)


func is_one_house() -> bool:
	return true


# ---------------------------------------------------------------- the start --

## A town has no yard of dead round a school: nothing is seeded (`Sim._seed` indexes the wall sections, which a town starts without).
func _seed() -> void:
	pass


## `Sim.start_run` puts four of the dead at the school's corners: the town's own dead are the field's.
func start_run(difficulty_index: int, seed_value: int) -> void:
	super(difficulty_index, seed_value)
	zombies.clear()


# ----------------------------------------------------------------- the base --

## The base module once the house is claimed, else null.
func _claimed_base():
	var b = get("base")
	return b if b != null and bool(b.claimed) else null


## The base's middle (where the night is "from"); before a claim the start house's, else the school's old answer.
func base_center() -> Vector2:
	var b = _claimed_base()
	if b != null:
		return b.center()
	var hs = get("houses")
	if hs != null and hs.has_method("start_house") and hs.has_method("house"):
		var h: Dictionary = hs.house(int(hs.start_house()))
		if h.has("rect"):
			var r: Rect2i = h.rect
			return Vector2(r.position) + Vector2(r.size) * 0.5
	return super()


func yard_middle() -> Vector2:
	var b = _claimed_base()
	return b.yard_middle() if b != null else super()


## Whether a point is in the base's yard (the fenced ground round the house); false before a claim.
func _in_yard(x: float, y: float) -> bool:
	var b = _claimed_base()
	return b != null and Rect2(b.yard_rect()).has_point(Vector2(x, y))


func _in_the_yard(x: float, y: float) -> bool:
	return _in_yard(x, y)


## Whether a point is on the floor of the claimed house (the school building's place).
func inside_school(x: float, y: float) -> bool:
	var b = _claimed_base()
	var hs = get("houses")
	return b != null and hs != null and int(hs.house_at(x, y)) == int(b.house)


## How many of the dead are in the yard or the house (not counting those on their way out): the stores are theirs to ruin. With no fence or gate built the barred doors
## are the base's outer wall (`yard_open`), so the lawn is still the street: only the dead in the house count, not a wanderer crossing the lot.
func dead_inside() -> int:
	if _claimed_base() == null:
		return 0
	var per = get("perimeter")
	var fenced: bool = per == null or not bool(per.no_outer_wall())
	var n := 0
	for z in zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "retreat":
			continue
		if (fenced and _in_yard(z.x, z.y)) or inside_school(z.x, z.y):
			n += 1
	return n


## A town has no school to open to the dead: a barred door that falls opens the door's own tiles (`open_segment`), nothing more.
func refresh_school() -> void:
	pass


## Whether any of the dead is coming at the base: on its way to a section (approach), clawing at it (attack) or in (breach), within THREAT_R
## tiles of its compound.
func _dead_coming() -> bool:
	var b = _claimed_base()
	if b == null:
		return false
	var comp: Rect2 = b.compound()
	for z in zombies:
		if z.state == "approach" or z.state == "attack" or z.state == "breach":
			var dx := maxf(maxf(comp.position.x - z.x, z.x - comp.end.x), 0.0)
			var dy := maxf(maxf(comp.position.y - z.y, z.y - comp.end.y), 0.0)
			if dx * dx + dy * dy <= THREAT_R * THREAT_R:
				return true
	return false


# ---------------------------------------------------------------- the nights --

func _attacks_on() -> bool:
	return scenario != null and scenario.has_method("attacks_on") and bool(scenario.attacks_on())


## The posts are manned at the call to arms and, once the attacks are on, as the colony's rules say; never before the fourth rescue.
func posts_manned() -> bool:
	if radio.alarm_on:
		return true
	if not _attacks_on():
		return false
	return super()


## The bell turns the wanderers into attackers only once the attacks are on (the streets are dangerous, but the dead do not come for the base).
func _wanderers_rally() -> bool:
	return _attacks_on()


## Whether the dead go for the base's doors (there is no outer wall yet, or a gate stands open) as they go for the school's.
func yard_open() -> bool:
	if super():
		return true
	var per = get("perimeter")
	return per != null and bool(per.no_outer_wall())


func _any_gate_open() -> bool:
	var per = get("perimeter")
	return per != null and bool(per.gate_open())


func _is_open_gate(s) -> bool:
	return String(s.kind) == "gate"


## The night's cap counts only the wave's dead: the street's own (they have a record in the field) do not eat its room.
func alive_for_cap() -> int:
	var f = get("field")
	var rec = f.get("rec_of") if f != null else null
	var alive := 0
	for z in zombies:
		if z.state != "dead" and z.state != "dying" and not (rec != null and rec.has(z)):
			alive += 1
	return alive


## At dawn only the night's own dead go back to the city; the town's stay where they are.
func _dawn_sweep() -> void:
	var f = get("field")
	var rec = f.get("rec_of") if f != null else null
	var left := DAWN_LEAVES_PER_STEP
	for z in zombies:
		if left <= 0:
			return
		if rec != null and rec.has(z):
			continue
		if z.state != "dying" and z.state != "dead" and z.state != "retreat":
			retreat(z)
			left -= 1


# --------------------------------------------------------------- the people --

## The dead of the street hunt at every hour in a town.
func _hunt_allowed() -> bool:
	return true


## Whether one of the dead is after this person within reach of their gun: a hunt (the colony's) or a chase (the town's): by day a person
## defends himself.
func _hunted(p: Person) -> bool:
	if super(p):
		return true
	for z in zombies:
		if z.state == "chase" and z.hunt_id == String(p.id):
			return true
	return false


## What a shooter picks: the dead at the fence (clawing it, or in through it) whatever stands between, and the rest only on a clear line
## (a house's wall hides what is behind it). No yard bonus: a base has the fence line, not the school's yard.
func _find_target(p: Person):
	var reach: float = reach_of(gun_of(p), p)
	var best = null
	var best_score := INF
	var from := Vector2(p.x, p.y)
	for z in zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dist := Vector2(z.x - p.x, z.y - p.y).length()
		if dist > reach:
			continue
		if z.state != "attack" and z.state != "breach" and not path_z.sight(world.solid_z, from, Vector2(z.x, z.y), 0.12):
			continue
		var score := dist - (3.0 if z.state == "attack" else 0.0) + float(Kinds.PRIORITY.get(z.kind, 0.0))
		if score < best_score:
			best_score = score
			best = z
	return best


# -------------------------------------------------------------------- saves --

## Before a save is read (`SaveGame.apply`, one generic hook): the base puts its layout in place, then the perimeter makes the sections of the
## slots that were built (the save finds them by id). Returns what was there, for `restore_load` when the save is refused.
func prepare_load(data: Dictionary):
	var before := {}
	var b = get("base")
	if b != null and b.has_method("prepare_load"):
		before["base"] = b.prepare_load(data)
	var per = get("perimeter")
	if per != null and per.has_method("prepare_load"):
		before["perimeter"] = per.prepare_load(data)
	return before


func restore_load(before) -> void:
	if not before is Dictionary:
		return
	var per = get("perimeter")
	if per != null and before.has("perimeter") and per.has_method("restore"):
		per.restore(before.perimeter)
	var b = get("base")
	if b != null and before.has("base") and b.has_method("restore"):
		b.restore(before.base)
