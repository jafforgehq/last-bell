## The avatar (round 17, slice 1): the one survivor the player plays, in the simulation. The views feed it the player's
## hands every frame (`set_input`: where to walk, the point of the world the mouse is over, the trigger; `reload()` and
## `melee()` are the two keys) and read the person back; the rules here do what a person does by themselves anywhere else
## in the sim (walk, aim, shoot, reload, swing) from those hands, and the AI leaves the person alone: `Sim._update_person`
## hands the player to `update`, so no goal, no order, no job and no auto-fire apply to them. Everyone else keeps their own
## AI. `Sim.player_id == ""` is the old game (the harness, the tests, Orientation Day): nothing here runs.
##
## WALKING. 3.2 tiles a second in the direction of `input_move` (a diagonal is no faster), a box 0.3 tiles to each side
## against the walking grid of the people (`world.solid_p`: walls, props, a wall section that stands, the rail and face
## of a walkway but not its ladders), one axis at a time so that a wall is slid along, in sub-steps so that nothing is
## jumped, and somebody found a hair inside a wall (a person taken over from the AI stands where the pathfinder left
## them) is pushed out of it, never through it. The raised decks need nothing of their own: their rails are in the grid.
## AIMING. The person faces the mouse (`facing`) and the gun points at it (`aim`, radians, from the shoulder, as the
## drawing wants it).
## SHOOTING. While the trigger is held and the gun is cool, loaded and not being reloaded, one round (a shell's pellets)
## leaves the muzzle along the aim, scattered inside a cone: the gun's `spread`, a worse shot for a poor Shooting skill,
## hunger, a wound or a shaken mind, wider with the kick of the last shots (`recoil`, `bloom`) and wider again while
## walking. Each pellet goes along its ray to the first of the dead whose body is within HIT_R of it, or to the first wall,
## or to the gun's reach; it hurts that one only (nothing goes through). A wall section of the yard is low (a shot goes
## over it from the walkway: the whole game); a prop or a building's wall, the walkway's own face and the edge of the map
## stop it. The cost in ammunition, the noise, the events and the effects are the NPC's (`Sim._fire`): a round from the
## stock (`shot_cost`), and with the stock too low for one the butt of the gun is swung instead; a pike thrusts.
## RELOADING. `reload()` (R) when the magazine is not full and there is ammunition; the gun's own time; the last round
## starts one by itself, and an empty magazine starts one when the trigger is let go.
## MELEE. `melee()` (F): an arc of MELEE_REACH tiles and MELEE_ARC degrees toward the aim hits every one of the dead in
## it once, with the pike's damage or the butt's, whatever the gun and with no ammunition; MELEE_COOLDOWN seconds between.
## SUCCESSION. When the player dies, turns or leaves (`on_player_lost`, called by medical.gd), the next in line (alive, up
## before down; the most trusted, then the best Leading, then the id) is the player; everyone's trust falls, a mourning
## shock goes through the morale, and a "succession" event is raised. The lost one's carried gear is lost with them:
## nothing in the sim carries any yet (a played trip's bags are the trip's, not a person's).
##
## Events this module adds to sim.events (besides the `shot`, `reload` and `stab` events of the NPCs' own fighting):
##   {"type": "succession", "from": id, "to": id}
## Saved: only the id of the player (the Person's own variables, the flag and the input among them, are saved with them).
extends RefCounted

const WALK_SPEED := 3.2
## Half the width of the avatar's box, in tiles.
const RADIUS := 0.3
## No walking sub-step is longer than this many tiles (a tile is one; nothing is jumped).
const MAX_SUBSTEP := 0.2
const EPS := 1.0e-4

## How far from a pellet's line the middle of a body can be and still be hit, times the creature's size. (The middle
## of a body is BODY tiles above its feet, where the NPCs aim.)
const HIT_R := 0.42
const BODY := 0.3
## A shot is followed along its line in steps of this many tiles.
const TRACE_STEP := 0.1
## The cone of a gun that names none (radians, all across), and what makes it wider: the kick (at 1.0, as much again) and
## walking (a little over half again). A shot adds BLOOM_PER_SHOT to the bloom, which lets go BLOOM_DECAY a second.
const DEFAULT_SPREAD := 0.05
const RECOIL_SPREAD := 1.0
const MOVE_SPREAD := 0.6
const BLOOM_PER_SHOT := 0.3
const BLOOM_DECAY := 1.5

const MELEE_REACH := 1.5
const MELEE_ARC := 100.0
const MELEE_COOLDOWN := 0.5
## The arc of a thrust (the pike's, or the butt's when the stock is dry), degrees.
const THRUST_ARC := 36.0
## Where a blow comes from: the chest, this far above the feet.
const CHEST := 0.15

## What a loss costs: every living person's trust in the player, and the morale of everyone (a shock, `morale.shock`).
const TRUST_LOSS := 10.0
const MOURNING := -8.0

var sim
## The tiles of the wall sections that a shot goes over, kept while a shot or a blow is worked out.
var _low := {}


func setup(s) -> void:
	sim = s


## A new run: nobody is the player (the caller names them with `set_player` after `start_run`).
func start() -> void:
	sim.player_id = ""
	for p in sim.people:
		p.player = false
		_clear_input(p)


func save() -> Dictionary:
	return {"player_id": sim.player_id}


## The flags of the people are loaded with them: the module's own word on who the player is wins over them.
func load_state(d: Dictionary) -> void:
	var id = d.get("player_id", "")
	sim.player_id = ""
	for p in sim.people:
		p.player = false
	if typeof(id) != TYPE_STRING or id == "":
		return
	for p in sim.people:
		if String(p.id) == id and not p.dead:
			sim.player_id = id
			p.player = true


# ----------------------------------------------------------------- the player --

## The person the player controls, or null (no avatar, or nobody of that id).
func player():
	if sim.player_id == "":
		return null
	for p in sim.people:
		if String(p.id) == sim.player_id:
			return p
	return null


## Makes a person (the object or their id) the player; null gives the avatar up. False, and nothing changes, for someone
## who is not in the crew or is gone. The new player is taken off their job and out of any order of the AI.
func set_player(who) -> bool:
	if who == null:
		for p in sim.people:
			if p.player:
				p.player = false
				_clear_input(p)
		sim.player_id = ""
		return true
	var target = _find(who)
	if target == null or target.dead or target.turned:
		return false
	for p in sim.people:
		if p != target and p.player:
			p.player = false
			_clear_input(p)
	sim.player_id = String(target.id)
	target.player = true
	_take_over(target)
	return true


func _find(who):
	for p in sim.people:
		if typeof(who) == TYPE_STRING:
			if String(p.id) == who:
				return p
		elif p == who:
			return p
	return null


## The AI lets go of a person who becomes the player.
func _take_over(p) -> void:
	sim.jobs.unassign(p)
	sim.tactics.call_back(p)
	p.drafted = false
	p.order = null
	p.repair = null
	p.target = null
	p.path = []
	p.goal_key = ""
	p.moving = false
	p.stance = ""
	p.stance_at = Vector2.ZERO
	_clear_input(p)


func _clear_input(p) -> void:
	p.input_move = Vector2.ZERO
	p.input_aim = Vector2.ZERO
	p.input_fire = false
	p.input_reload = false
	p.input_melee = false


# ---------------------------------------------------------------- the hands --

## The player's hands for the coming steps: the direction to walk (any length), the point of the world, in tiles, that the
## mouse is over, and whether the trigger is held. Called every frame by the view.
func set_input(move: Vector2, aim: Vector2, fire: bool) -> void:
	var p = player()
	if p == null:
		return
	p.input_move = move
	p.input_aim = aim
	p.input_fire = fire


## The reload key: taken at the next step. False when there is no player or they cannot.
func reload() -> bool:
	var p = player()
	if p == null or p.dead or p.downed:
		return false
	p.input_reload = true
	return true


## The melee key: taken at the next step.
func melee() -> bool:
	var p = player()
	if p == null or p.dead or p.downed:
		return false
	p.input_melee = true
	return true


# ----------------------------------------------------------------- the step --

## One step of the player's person (called by `Sim._update_person` instead of the goals and the auto-fire).
func update(p, dt: float) -> void:
	p.cooldown = maxf(0.0, p.cooldown - dt)
	p.melee_t = maxf(0.0, p.melee_t - dt)
	p.bloom = maxf(0.0, p.bloom - dt * BLOOM_DECAY)
	p.target = null
	if p.reloading > 0.0:
		p.reloading -= dt
		if p.reloading <= 0.0:
			p.reloading = 0.0
			p.mag = int(p.gun.get("mag", 0))
	_move(p, dt)
	_aim(p)
	if p.input_reload:
		p.input_reload = false
		_start_reload(p)
	if p.input_melee:
		p.input_melee = false
		_swing(p)
	var ranged: bool = not p.gun.get("melee", false)
	if p.input_fire:
		if p.cooldown <= 0.0 and p.reloading <= 0.0:
			_trigger(p)
	elif ranged and p.mag <= 0 and p.reloading <= 0.0:
		_start_reload(p)
	if p.reloading > 0.0:
		p.activity = "Reloading"
	elif p.input_fire:
		p.activity = "Firing"
	elif p.moving:
		p.activity = "On the move"
	else:
		p.activity = "Ready"


# ------------------------------------------------------------------ walking --

func _blocked(x: float, y: float) -> bool:
	var solid: PackedByteArray = sim.world.solid_p
	var w: int = sim.W
	var h: int = sim.H
	for ty in range(floori(y - RADIUS + EPS), floori(y + RADIUS - EPS) + 1):
		for tx in range(floori(x - RADIUS + EPS), floori(x + RADIUS - EPS) + 1):
			if tx < 0 or ty < 0 or tx >= w or ty >= h or solid[ty * w + tx] != 0:
				return true
	return false


## Somebody a hair inside a wall is pushed out of it by the least way. False when they are buried so deep that there is
## no free place within reach (then they walk out unhindered).
func _unstick(p) -> bool:
	if not _blocked(p.x, p.y):
		return true
	for r in range(1, 13):
		var d := 0.05 * float(r)
		for v in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			if not _blocked(p.x + v.x * d, p.y + v.y * d):
				p.x += v.x * d
				p.y += v.y * d
				return true
	return false


func _move(p, dt: float) -> void:
	p.moving = false
	var free_standing := _unstick(p)
	var dir: Vector2 = p.input_move
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var total := WALK_SPEED * dt
	var n := maxi(1, ceili(total / MAX_SUBSTEP))
	var step := total / float(n)
	var moved := 0.0
	for i in n:
		var before := Vector2(p.x, p.y)
		if dir.x != 0.0:
			var nx: float = p.x + dir.x * step
			if free_standing and _blocked(nx, p.y):
				nx = _slide_x(p, nx)
			p.x = nx
		if dir.y != 0.0:
			var ny: float = p.y + dir.y * step
			if free_standing and _blocked(p.x, ny):
				ny = _slide_y(p, ny)
			p.y = ny
		moved += before.distance_to(Vector2(p.x, p.y))
	if not free_standing:
		# (buried in a wall: they walk out of it, but never off the map)
		p.x = clampf(p.x, RADIUS, float(sim.W) - RADIUS)
		p.y = clampf(p.y, RADIUS, float(sim.H) - RADIUS)
	if moved > 0.001:
		p.moving = true
		p.walk_phase += moved * 3.4


## Where a step along x that would end in a wall ends instead: against it (the box's edge on the tile's).
func _slide_x(p, nx: float) -> float:
	var at := nx
	if nx > p.x:
		at = float(floori(nx + RADIUS - EPS)) - RADIUS
	else:
		at = float(floori(nx - RADIUS + EPS) + 1) + RADIUS
	if (nx > p.x and at < p.x) or (nx < p.x and at > p.x) or _blocked(at, p.y):
		return p.x
	return at


func _slide_y(p, ny: float) -> float:
	var at := ny
	if ny > p.y:
		at = float(floori(ny + RADIUS - EPS)) - RADIUS
	else:
		at = float(floori(ny - RADIUS + EPS) + 1) + RADIUS
	if (ny > p.y and at < p.y) or (ny < p.y and at > p.y) or _blocked(p.x, at):
		return p.y
	return at


# ------------------------------------------------------------------- aiming --

## The point the gun is held at, from the shoulder.
func shoulder(p) -> Vector2:
	var view: String = "E" if p.facing == "W" else p.facing
	var pv: Vector2 = sim.PIVOT[view]
	return Vector2(p.x - pv.x if p.facing == "W" else p.x + pv.x, p.y + pv.y)


## Facing and aim from the mouse (or, with no mouse yet, from the way they walk).
func _aim(p) -> void:
	var at: Vector2 = p.input_aim
	var has_aim: bool = at != Vector2.ZERO
	var look := Vector2.ZERO
	if has_aim:
		look = at - Vector2(p.x, p.y)
	elif p.moving:
		look = p.input_move
	if look.length() < 0.05:
		return
	p.facing = sim.facing_of(look.x, look.y, p.facing)
	var to: Vector2 = (at - shoulder(p)) if has_aim else look
	if to.length() > 0.1:
		p.aim = to.angle()


# ----------------------------------------------------------------- shooting --

## The cone, in radians all across, of the next shot of this gun.
func spread_of(p, gun: Dictionary) -> float:
	var skill := clampf(1.6 - 0.08 * float(p.skills.get("Shooting", 0)), 0.8, 1.6)
	var steady := clampf(sim.aim_factor(p) * sim.perf(p), 0.5, 1.5)
	var kick := maxf(p.recoil, p.bloom)
	var walking := 1.0 + (MOVE_SPREAD if p.moving else 0.0)
	return float(gun.get("spread", DEFAULT_SPREAD)) * skill / steady * (1.0 + RECOIL_SPREAD * kick) * walking


func _trigger(p) -> void:
	var gun: Dictionary = sim.gun_of(p)
	if gun.get("melee", false):
		# a pike, or the butt of a gun the stock cannot feed
		p.cooldown = float(gun.cooldown)
		_strike(p, float(gun.range), deg_to_rad(THRUST_ARC) / 2.0, float(gun.dmg))
		return
	if p.mag <= 0:
		return    # (it clicks: reload, or let go of the trigger)
	_shoot(p, gun)


func _shoot(p, gun: Dictionary) -> void:
	var spread := spread_of(p, gun)
	p.mag -= 1
	p.stats.shots += 1
	p.recoil = 1.0
	p.bloom = minf(1.0, p.bloom + BLOOM_PER_SHOT)
	p.cooldown = float(gun.cooldown)
	var m: Vector2 = sim.muzzle(p, p.aim)
	sim.fx.muzzle(m.x, m.y, p.aim, p.weapon == "shotgun" or p.weapon == "hunting")
	sim.fx.casing(p.x, p.y - 0.15, p.aim, p.weapon == "shotgun")
	sim.events.append({"type": "shot", "weapon": gun.sound, "x": p.x, "y": p.y})
	sim.stock.ammo = maxf(0.0, sim.stock.ammo - sim.shot_cost(p))
	var from := shoulder(p)
	var reach: float = sim.reach_of(gun, p)
	var dmg := float(gun.dmg)
	var dealt := {}
	for k in int(gun.get("pellets", 1)):
		var pa: float = p.aim + (sim.rng.randf() - 0.5) * spread
		var res := trace(from, pa, reach)
		if res.z != null:
			dealt[res.z] = float(dealt.get(res.z, 0.0)) + dmg
		else:
			sim.fx.smoke(res.end.x, res.end.y, 0.12, false)
			# (a shot stopped by a wall, not one that ran out of reach, throws sparks where it struck)
			if res.end.distance_to(from) < reach - 0.15:
				sim.fx.hit_material(res.end.x, res.end.y, "metal")
		sim.fx.tracer(m.x, m.y, res.end.x, res.end.y)
	for z in dealt:
		sim._hurt_zombie(z, float(dealt[z]), p.aim, p)
	if p.mag <= 0:
		p.target = null
		_start_reload(p)
	sim._shot_noise(p)


## Follows a shot from `from` along `ang` for `reach` tiles: {"z": the first of the dead hit (or null), "end": where it
## stopped}. The dead hit are the nearest whose body is within HIT_R (times their size) of the line before any wall. (The
## views can use it for an aim line.)
func trace(from: Vector2, ang: float, reach: float) -> Dictionary:
	_low = _low_tiles()
	var dir := Vector2.from_angle(ang)
	var stop := _wall_distance(from, dir, reach)
	var best = null
	var best_t := stop
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var c := Vector2(z.x, z.y - BODY) - from
		var along := c.dot(dir)
		if along < 0.0 or along > best_t:
			continue
		if absf(c.cross(dir)) > HIT_R * float(z.size):
			continue
		best = z
		best_t = along
	return {"z": best, "end": from + dir * best_t}


## How far along a line from `from` toward `dir` a shot goes before a wall, up to `reach`.
func _wall_distance(from: Vector2, dir: Vector2, reach: float) -> float:
	var t := 0.0
	while t < reach:
		if _stops(from + dir * t):
			return t
		t += TRACE_STEP
	return reach


func _stops(pt: Vector2) -> bool:
	var tx := floori(pt.x)
	var ty := floori(pt.y)
	if tx < 0 or ty < 0 or tx >= sim.W or ty >= sim.H:
		return true
	var i: int = ty * sim.W + tx
	return sim.world.solid_p[i] != 0 and not _low.has(i)


## The tiles of the wall sections that a shot goes over: the yard's walls are barricades, shot over from the walkway
## (a school door is a building's wall and is not).
func _low_tiles() -> Dictionary:
	var out := {}
	for s in sim.segments:
		if s.kind == sim.DOOR_KIND:
			continue
		for i in s.tiles:
			out[int(i)] = true
	return out


## Whether a wall is between two points (for a blow).
func _wall_between(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	return d > 0.01 and _wall_distance(a, (b - a) / d, d) < d - 0.05


# ------------------------------------------------------------------- reload --

## Starts a reload if there is one to do: a gun that is not a pike, a magazine that is not full, ammunition to put in it.
func _start_reload(p) -> bool:
	if p.gun.get("melee", false) or p.reloading > 0.0:
		return false
	if p.mag >= int(p.gun.get("mag", 0)) or sim.stock.ammo < sim.shot_cost(p):
		return false
	p.reloading = float(p.gun.reload) * sim.traits.mult(p, "reload")
	sim.events.append({"type": "reload", "x": p.x, "y": p.y})
	return true


# -------------------------------------------------------------------- melee --

## The melee key: a swing of the arc, at most once in MELEE_COOLDOWN seconds, with the pike's damage or the butt's.
func _swing(p) -> void:
	if p.melee_t > 0.0:
		return
	p.melee_t = MELEE_COOLDOWN
	p.cooldown = maxf(p.cooldown, MELEE_COOLDOWN)
	var weapon: Dictionary = p.gun if p.gun.get("melee", false) else sim.BUTT
	_strike(p, MELEE_REACH, deg_to_rad(MELEE_ARC) / 2.0, float(weapon.dmg))


## A blow at everything of the dead within `reach` tiles of the chest and `half_arc` radians either side of the aim, once
## each, with no wall between. Returns how many were struck.
func _strike(p, reach: float, half_arc: float, dmg: float) -> int:
	_low = _low_tiles()
	p.thrust = 1.0
	sim.events.append({"type": "stab", "x": p.x, "y": p.y})
	var from := Vector2(p.x, p.y - CHEST)
	var hits := 0
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var c := Vector2(z.x, z.y - BODY)
		var v := c - from
		var dist := v.length()
		if dist > reach:
			continue
		if dist > 0.3 and absf(sim.ang_diff(p.aim, v.angle())) > half_arc:
			continue
		if _wall_between(from, c):
			continue
		sim._hurt_zombie(z, dmg, v.angle(), p, true)
		hits += 1
	return hits


# --------------------------------------------------------------- succession --

## The player is gone (died, turned, or left through the gate): the next in line takes over. With nobody left there is
## nothing to do (the scenario's defeat). `successor` names who takes over when the one who fell was not the colony's to
## replace (a place's squad chose its own leader while the base was told: raid_scene.gd); a missing or unfit one is the next
## in line as ever.
func on_player_lost(p, successor = null) -> void:
	if p == null or not p.player:
		return
	var next = successor if successor != null and successor != p and sim.people.has(successor) and not successor.dead and not successor.turned else _next_in_line(p)
	if next == null:
		return
	p.player = false
	_clear_input(p)
	sim.player_id = String(next.id)
	next.player = true
	_take_over(next)
	for q in sim.people:
		if not q.dead:
			q.trust = clampf(q.trust - TRUST_LOSS, 0.0, 100.0)
	sim.morale.shock(null, MOURNING, "Lost %s" % p.first)
	sim.events.append({"type": "succession", "from": String(p.id), "to": String(next.id)})
	sim.alert("succession", "warn", "You are %s now" % next.first, "%s is gone" % p.first, Vector2(next.x, next.y) if next.away == null else null, 20.0)


## Who leads next: anyone alive (away on a trip too), those who can stand before those who are down, then the most trusted,
## the best Leading, and the id.
func _next_in_line(lost):
	var best = null
	for q in sim.people:
		if q == lost or q.dead or q.turned:
			continue
		if best == null or _before(q, best):
			best = q
	return best


func _before(a, b) -> bool:
	if a.downed != b.downed:
		return not a.downed
	if not is_equal_approx(a.trust, b.trust):
		return a.trust > b.trust
	var la := int(a.skills.get("Leading", 0))
	var lb := int(b.skills.get("Leading", 0))
	if la != lb:
		return la > lb
	return String(a.id) < String(b.id)
