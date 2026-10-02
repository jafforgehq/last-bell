## The dead in the streets by day (round 12, the settlement game only: the classic start has none of this).
## The city is not empty when the dead have drifted back at dawn: each morning stragglers who did not leave are
## about the streets (more as the days go on, up to DAY_MAX), shambling about; one that sees a living person
## outside the walls (within NOTICE_R, with a way to them) hunts them until it loses them or is shot. People shoot
## at hunters by day (see `sim._combat`). If the streets are open at the mouths the ring has its share of them;
## once every street is walled the stragglers are only outside it. Those still about when the bell rings join the
## night's dead as the other wanderers do.
##
## Events: none. Alerts: `streets` (once each morning).
extends RefCounted

## The stragglers each morning: this many, and this many more for each day gone, never more than DAY_MAX.
const DAY_BASE := 2.0
const DAY_PER_DAY := 0.25
const DAY_MAX := 8
## A straggler hunts someone this near it that it can walk to; it is shaken off at GIVE_UP.
const NOTICE_R := 7.0
const GIVE_UP := 14.0
## They are put where nobody is this near, on asphalt or sidewalk (terrain ids 1 and 2).
const SAFE_FROM_PEOPLE := 10.0
const STREET_TERRAIN := [1, 2]
const TRIES := 60
## How often (seconds of rules time) a straggler looks about for someone.
const LOOK_EVERY := 0.5

var sim
var _look_t := 0.0
## The harness switches the streets off with this (to see what they change).
var enabled := true


func setup(s) -> void:
	sim = s


func start() -> void:
	_look_t = 0.0


## How many stragglers a morning of this day puts in the streets.
func target_count(day: int) -> int:
	return mini(DAY_MAX, int(floorf(DAY_BASE + DAY_PER_DAY * float(maxi(day, 1) - 1))))


## How many of the dead are about the streets now (wandering or hunting).
func street_dead() -> int:
	var n := 0
	for z in sim.zombies:
		if z.state == "wander" or z.state == "hunt":
			n += 1
	return n


## The morning: the stragglers are put in the streets (up to the day's number, counting those still about).
func on_dawn() -> void:
	if not enabled or not sim.town.on:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (sim.run_seed * 2654435761 + sim.day * 40503 + 55555) & 0x7fffffff
	var regions := {}
	for sp in sim.spawns:
		var r: int = sim.region_at(sp.x, sp.y)
		if r >= 0:
			regions[r] = true
	var want := target_count(sim.day) - street_dead()
	var placed := 0
	for i in maxi(0, want):
		var at := _street_spot(rng, regions)
		if at == Vector2(-1.0, -1.0):
			break
		var z = sim.spawn(at.x, at.y, "wander")
		z.wander_t = rng.randf() * 4.0
		placed += 1
	if placed > 0:
		sim.alert("streets", "info", "The dead are in the streets", "%d about this morning" % street_dead(), null, 14.0)


## A tile of street, open to the dead and joined to a spawn point (so the ring only while a street is open),
## away from the people; (-1, -1) when none was found.
func _street_spot(rng: RandomNumberGenerator, regions: Dictionary) -> Vector2:
	for t in TRIES:
		var x: int = rng.randi() % sim.W
		var y: int = rng.randi() % sim.H
		if not STREET_TERRAIN.has(int(sim.world.terrain[y * sim.W + x])):
			continue
		if sim.world.solid_z[y * sim.W + x] != 0:
			continue
		if not regions.has(sim.region_at(float(x) + 0.5, float(y) + 0.5)):
			continue
		var at := Vector2(float(x) + 0.5, float(y) + 0.5)
		var near := false
		for p in sim.people:
			if not p.dead and Vector2(p.x, p.y).distance_to(at) < SAFE_FROM_PEOPLE:
				near = true
				break
		if not near:
			return at
	return Vector2(-1.0, -1.0)


func update(dt: float) -> void:
	if not enabled or not sim.town.on or sim.phase != "day":
		return
	_look_t -= dt
	if _look_t > 0.0:
		return
	_look_t = LOOK_EVERY
	for z in sim.zombies:
		if z.state != "wander":
			continue
		var best = null
		var best_d := NOTICE_R
		var zr: int = sim.region_at(z.x, z.y)
		for p in sim.people:
			if p.dead or p.downed or p.away != null:
				continue
			var d := Vector2(p.x - z.x, p.y - z.y).length()
			if d < best_d and sim.region_at(p.x, p.y) == zr:
				best_d = d
				best = p
		if best != null:
			z.state = "hunt"
			z.hunt_id = String(best.id)
			z.path = []
			z.repath = 0.0
