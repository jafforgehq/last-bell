## The rules of the town (feature/town-core): the colony's Sim as a place plays it (raid_sim.gd) with the three changes that a 192 x 192 town of
## hundreds of dead needs, each switchable so that the cost of the old way can be measured against the new:
##
##  1. `_separate` (the dead's crowd pass) is a square of how many there are in the old code (sim.gd `_separate`: every pair, every step); here a
##     grid of one tile (`grid_separate`), and two dead that both stand still are not asked.
##  2. a new state "chase" in place of "hunt" (`chase_on`): hunt gives a dead one up at 14 tiles (Streets.GIVE_UP), asks the region of both
##     (a flood of the whole map the first time and after every door, wall or build) and searches a way every 0.8 s; chase gives up at
##     `chase_give_up` (45), never asks a region, walks straight at the prey when a line of sight is clear and searches the grid only when it is not,
##     less often the farther the prey.
##  3. a new state "still" (stands where it is: the base `match` has no case for it, so the preamble of `_update_zombie` is all it costs).
##
## The noise of a shot goes to `on_noise` (the field's wake, scripts/town/dormant_dead.gd) instead of the base's loop over every dead one.
extends "res://scripts/raid/raid_sim.gd"

const GRID_W := 1024

var grid_separate := true
var chase_on := true
var chase_give_up := 45.0
## Called with the place of a shot: the dormant field wakes what is near it.
var on_noise: Callable
var _grid := {}
## Microseconds spent in `_separate`, and how many chases were started, for the measurements (the reader resets them).
var sep_usec := 0
var chase_usec := 0
var chase_n := 0


func _init(data: Dictionary, w, effects) -> void:
	super(data, w, effects)


func _shot_noise(p: Person) -> void:
	if on_noise.is_valid():
		on_noise.call(Vector2(p.x, p.y))


func _update_zombie(z: Zombie, dt: float) -> void:
	var was_staggered := z.stagger > 0.0
	super(z, dt)
	if z.state == "chase" and not was_staggered:
		var t_in := Time.get_ticks_usec()
		_chase(z, dt)
		chase_usec += Time.get_ticks_usec() - t_in
		chase_n += 1


## Starts one of the dead after somebody (a person of the sim): chase, or the base's hunt when `chase_on` is off.
func start_chase(z: Zombie, prey: Person) -> void:
	z.state = "chase" if chase_on else "hunt"
	z.hunt_id = String(prey.id)
	z.path = []
	z.path_i = 0
	z.repath = rng.randf() * 0.3


func _prey_of(z: Zombie) -> Person:
	for p in people:
		if String(p.id) == z.hunt_id and not p.dead and not p.downed and p.away == null:
			return p
	# the one they were after is gone: the nearest of the living
	var best: Person = null
	var bd := INF
	for p in people:
		if p.dead or p.downed or p.away != null:
			continue
		var d := Vector2(p.x - z.x, p.y - z.y).length()
		if d < bd:
			bd = d
			best = p
	if best != null:
		z.hunt_id = String(best.id)
	return best


func _chase(z: Zombie, dt: float) -> void:
	var prey := _prey_of(z)
	if prey == null:
		z.state = "wander"
		z.hunt_id = ""
		return
	var dx := prey.x - z.x
	var dy := prey.y - z.y
	var dist := sqrt(dx * dx + dy * dy)
	if dist > chase_give_up:
		z.state = "wander"
		z.hunt_id = ""
		z.path = []
		return
	if dist < 0.7:
		z.facing = facing_of(dx, dy, z.facing)
		z.attack_t -= dt
		if z.attack_t <= 0.0:
			z.attack_t = 1.3
			_bite(z, prey)
		return
	z.repath -= dt
	if z.repath <= 0.0 or z.path.is_empty() or z.path_i >= z.path.size():
		var me := Vector2(z.x, z.y)
		var you := Vector2(prey.x, prey.y)
		if dist < 14.0 and path_z.sight(world.solid_z, me, you, 0.3):
			z.path = [you]
			z.path_i = 0
			z.repath = 0.25 + rng.randf() * 0.15
		else:
			z.path = path_z.find(world.solid_z, z.x, z.y, prey.x, prey.y)
			z.path_i = 0
			z.repath = clampf(dist * 0.05, 0.6, 2.5) + rng.randf() * 0.5
			if z.path.is_empty():
				z.state = "wander"
				z.hunt_id = ""
				return
	var slow := z.speed * (0.85 if z.limp else 1.0)
	_follow(z, slow * 1.1, dt)


## The crowd pass on a grid of one tile: the pairs the base asks (each pair once, nearer than sqrt(0.3)), not the square of everything.
func _separate() -> void:
	if not grid_separate:
		var t_old := Time.get_ticks_usec()
		super()
		sep_usec += Time.get_ticks_usec() - t_old
		return
	var t_in := Time.get_ticks_usec()
	var zs := zombies
	var n := zs.size()
	_grid.clear()
	for i in n:
		var a: Zombie = zs[i]
		if a.state == "dead" or a.state == "dying":
			continue
		var key := floori(a.y) * GRID_W + floori(a.x)
		var cell = _grid.get(key)
		if cell == null:
			_grid[key] = [i]
		else:
			cell.append(i)
	for i in n:
		var a: Zombie = zs[i]
		if a.state == "dead" or a.state == "dying":
			continue
		var cx := floori(a.x)
		var cy := floori(a.y)
		var a_still := a.state == "still"
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cell = _grid.get((cy + dy) * GRID_W + cx + dx)
				if cell == null:
					continue
				for j in cell:
					if j <= i:
						continue
					var b: Zombie = zs[j]
					if a_still and b.state == "still":
						continue
					var ex := b.x - a.x
					var ey := b.y - a.y
					var d2 := ex * ex + ey * ey
					if d2 > 0.3 or d2 < 1e-6:
						continue
					var dist := sqrt(d2)
					var push := (0.55 - dist) * 0.5
					var ux := ex / dist
					var uy := ey / dist
					var ma := a.state != "attack"
					var mb := b.state != "attack"
					if ma:
						_nudge(a, -ux * push * (1.0 if mb else 2.0), -uy * push * (1.0 if mb else 2.0))
					if mb:
						_nudge(b, ux * push * (1.0 if ma else 2.0), uy * push * (1.0 if ma else 2.0))
	sep_usec += Time.get_ticks_usec() - t_in
