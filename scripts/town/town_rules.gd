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
##
## THE SIEGE (below, "the siege"): how the night's dead come at a base: in surges with lulls, together, to the nearest section or barred door, and mustering when there is no free place.
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


# ----------------------------------------------------------------- the siege --
##
## A night in the town is a SIEGE, not a trickle (the lab found that 22 of 24 idle avatars held the first attack: the dead came one at a time, the places at the barred doors
## were four and the rest of the wave wandered off into the street, out of every gun's reach). What changed, all of it here and in the data (`night` of one_house.json):
##   1. THE PACE. The night's dead are let in in a few SURGES with lulls between (`night.surges`: [{"at": hours after the dusk begins, "share": of the night's dead}], and
##      `night.surge_gap`, seconds between the groups of a surge): `update` holds the wave's timer (`spawn_t`) in a lull and lets it run fast in a surge. The forecast
##      (`wave_let_in`, asked by `Waves._arrival_seconds`) tells the same times.
##   2. THE CHOICE. The dead choose among ALL the base's sections that stand: the fence, the gate, and the barred doors (a ring with gaps in it is a way in to the doors), by how
##      near their approach side is, how crowded the section is and a little luck; the choice is tried against the walking grid for the best few, not the best one only.
##   3. NOBODY WANDERS. A dead one of the night with no free place (the sections are crowded, or no way) does not go off to wander: it musters, in the street just outside the
##      wall, where the guns reach it, and asks again for a place every second or so (one frees when its owner is shot).
## Everything is the base's (a claimed house): without one the colony's own rules answer, and the school's golden games never come here.

## How many of the best places a dead one tries to find a way to before it gives up for a moment.
const SIEGE_TRIES := 3
## Seconds between a mustering dead one's looks for a free place.
const MUSTER_ASK_S := 1.0
## How far outside its place's approach point a mustering dead one stands, in tiles (a little each, so they do not stand in one tile).
const MUSTER_BACK_MIN := 0.6
const MUSTER_BACK_SPAN := 2.2


## The night's `surges` of the data ([] when the scenario has none or there is none: the colony's own pace).
func _surges() -> Array:
	if scenario == null or not scenario.has_method("d"):
		return []
	var nd = scenario.d().get("night", {})
	var list = nd.get("surges", []) if nd is Dictionary else []
	return list if list is Array else []


## Seconds between the groups of a surge.
func _surge_gap() -> float:
	var nd = scenario.d().get("night", {}) if scenario != null and scenario.has_method("d") else {}
	return maxf(float(nd.get("surge_gap", 0.8)) if nd is Dictionary else 0.8, 0.1)


## The number of the night's queue by which surge `k` of `n` dead is done (the last takes what is left).
func _surge_goal(surges: Array, k: int, n: int) -> int:
	if k >= surges.size() - 1:
		return n
	var cum := 0.0
	for i in k + 1:
		cum += float(surges[i].get("share", 0.0))
	return clampi(roundi(cum * float(n)), 0, n)


## When the `i`th of `n` is let in (seconds from the dusk's start): its surge's start, and the surge's groups one after the other.
func wave_let_in(i: int, n: int, seconds: float) -> float:
	var surges := _surges()
	if surges.is_empty():
		return seconds
	var first := 0
	for k in surges.size():
		var goal := _surge_goal(surges, k, n)
		if i < goal:
			var from := float(surges[k].get("at", 0.0)) * 60.0 / maxf(min_per_sec, 0.01)
			return from + float(i - first) * _surge_gap() / 2.5
		first = goal
	return seconds


## Hours since the dusk began (0 to 24).
func _hours_since_dusk() -> float:
	return fposmod(float(hour) - float(seasons.dusk_hour()), 24.0)


## The wave's own timer is held back in a lull and let run in a surge (`Waves.update` spends `spawn_t`).
func update(dt: float) -> void:
	_pace_the_night()
	super(dt)


func _pace_the_night() -> void:
	if not waves.enabled or not _attacks_on() or (phase != "dusk" and phase != "night") or waves.night_day != day:
		return
	var surges := _surges()
	if surges.is_empty():
		return
	var n: int = waves.plan_for(day).queue.size()
	if waves.spawned >= n:
		return
	var since := _hours_since_dusk()
	var running := false
	for k in surges.size():
		if since < float(surges[k].get("at", 0.0)):
			break
		if waves.spawned < _surge_goal(surges, k, n):
			running = true
			break
	spawn_t = minf(spawn_t, _surge_gap()) if running else maxf(spawn_t, 1.0)


## The dead of a surge come TOGETHER: the colony draws each one's pace from the whole range of its kind (a walker's is 0.5 to 0.85 tiles a second, and 4 in 10 limp), so a group that
## set out in one clump reaches a wall one by one over half a minute and the guns shoot each as it comes. The night's `approach` dead are drawn close to their kind's mean pace
## (`night.tight`, 0 the colony's own spread, 1 all alike) and none limps.
func spawn(x: float, y: float, state: String, kind: String = "walker") -> Zombie:
	var z := super(x, y, state, kind)
	if state == "approach" and _claimed_base() != null and _attacks_on():
		var nd = scenario.d().get("night", {}) if scenario.has_method("d") else {}
		var tight := clampf(float(nd.get("tight", 0.85)) if nd is Dictionary else 0.85, 0.0, 1.0)
		var k: Dictionary = Kinds.KINDS[kind]
		z.speed = lerpf(z.speed, (float(k.speed[0]) + float(k.speed[1])) * 0.5, tight)
		if tight > 0.0:
			z.limp = false
	return z


## Every section of the base that can be clawed at: the fence, the gate, the barred doors (those of the lots are not the base's).
func _siege_sections() -> Array:
	var out: Array = []
	var gate_open: bool = _any_gate_open()
	for s in segments:
		if s.state == 3 or int(s.id) >= Lots.FIRST_SEGMENT_ID:
			continue
		if gate_open and _is_open_gate(s):
			continue    # (the gate stands open: nothing to claw at, they walk in)
		out.append(s)
	return out


## Gives one of the dead a free place at the section it comes to: the best by distance to the place's approach point, how crowded the section is, and a little luck (the
## section with the alarm on it scores far better); only at `only` when that is given. The doors are always among them. The best few are tried against the walking grid.
func assign_slot(z: Zombie, only) -> bool:
	if _claimed_base() == null:
		return super(z, only)
	var lured = tactics.lure_seg()
	var picks: Array = []
	for s in _siege_sections():
		if only != null and s != only:
			continue
		var crowd := 0
		for sl in s.slots:
			if sl.who != null:
				crowd += 1
		for sl in s.slots:
			if sl.who != null:
				continue
			var score := Vector2(sl.ax - z.x, sl.ay - z.y).length() + float(crowd) * 1.2 + rng.randf() * 4.0
			if lured != null and s == lured:
				score -= Tactics.LURE_PULL
			picks.append([score, sl])
	if picks.is_empty():
		return false
	picks.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(SIEGE_TRIES, picks.size()):
		var sl = picks[i][1]
		var path: Array = path_z.find(world.solid_z, z.x, z.y, sl.ax, sl.ay)
		if not path.is_empty():
			sl.who = z
			z.slot = sl
			z.path = path
			z.path_i = 0
			return true
	return false


## One of the dead on its way to the wall with no place (the sections are crowded): it musters in the street, a few tiles off the wall, and asks again for a place now and then.
## True when this step is spent (the colony's own step is not taken), false when it has a place now and the colony's step walks it there.
func _siege_hold(z: Zombie, dt: float) -> bool:
	if _breached() and rng.randf() < dt:
		z.state = "breach"    # (as the colony's arm: a wall is down and the dead near it come in)
		z.path = []
		z.path_i = 0
		return true
	z.repath -= dt
	if z.repath <= 0.0:
		z.repath = MUSTER_ASK_S * (0.8 + 0.5 * rng.randf())
		if assign_slot(z, null):
			return false
		_muster_path(z)
	z.t += dt
	z.moving = false
	z.groan_t -= dt
	if z.groan_t <= 0.0:
		z.groan_t = 5.0 + rng.randf() * 12.0
		events.append({"type": "groan", "x": z.x, "y": z.y, "kind": z.kind, "stray": false})
	_follow(z, z.speed * (0.85 if z.limp else 1.0), dt)
	return true


## A way to a stand just outside the nearest place's approach point (taken or not), for a dead one with no place of its own.
func _muster_path(z: Zombie) -> void:
	var best = null
	var best_d := INF
	for s in _siege_sections():
		for sl in s.slots:
			var dd := Vector2(sl.ax - z.x, sl.ay - z.y).length()
			if dd < best_d:
				best_d = dd
				best = sl
	if best == null:
		return
	var out := Vector2(best.ax - best.x, best.ay - best.y)
	out = out.normalized() if out.length() > 0.01 else Vector2.ZERO
	var back := MUSTER_BACK_MIN + MUSTER_BACK_SPAN * rng.randf()
	var at := Vector2(best.ax, best.ay) + out * back + Vector2(-out.y, out.x) * (rng.randf() - 0.5) * 2.0
	if world.is_solid(world.solid_z, at.x, at.y):
		at = Vector2(best.ax, best.ay)
	if Vector2(z.x, z.y).distance_to(at) < 0.8:
		z.path = []
		z.path_i = 0
		return
	z.path = path_z.find(world.solid_z, z.x, z.y, at.x, at.y)
	z.path_i = 0


func _update_zombie(z: Zombie, dt: float) -> void:
	if z.state == "approach" and z.slot == null and z.stagger <= 0.0 and _claimed_base() != null and _attacks_on() and _siege_hold(z, dt):
		return
	super(z, dt)


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
