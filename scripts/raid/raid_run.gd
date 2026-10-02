## A played trip (round 14). The squad goes into a place the generator made (scripts/raid/site_gen.gd: a map, its
## containers to search and its dead), the player gives orders, and the run says what came of it in the trip's
## result format (`result()`: loot, hurt, lost, clear, rescue, ammo_used, beats), so that it can stand where the
## dice's result stood (scavenge.gd, `scavenge.send_played`).
##
## THE PEOPLE are copies of the colony's (skills, traits, weapon, health; they are drafted, so they fire at what is
## in reach as in the yard, and stand where they are ordered). THE DEAD of the site are "still" (they stand until
## they notice someone: within NOTICE_R and in sight, or a shot within NOISE_R) or wander; one that notices hunts
## (the Sim's "hunt" state: it chases the one it saw and bites). A person bitten is hurt (a bite, for the colony's
## infection rules); a person brought down is lost unless a friend gets to them (HELP_S standing beside them).
## SEARCHING a container: stand at it for its `search_s`; what it holds goes in the squad's bags (CARRY each, more
## with a vehicle) and what does not fit stays. RETREAT: everyone walks to the exit; the run is over when every
## living member is there (or none is left).
##
## Time is the player's: `update(dt)` is called by the scene with real seconds; nothing here reads a clock.
extends RefCounted

const RaidSim := preload("res://scripts/raid/raid_sim.gd")

## How far the dead notice a person if there is a clear line, and how far a shot is heard.
const NOTICE_R := 7.0
const NOISE_R := 12.0
## How long a friend must stand beside someone who is down to get them up, and what they get up with.
const HELP_S := 4.0
const GET_UP_HP := 25.0
## What each person can carry (units of loot), and what a vehicle adds.
const CARRY := 30
const VEHICLE_CARRY := 80
const Vehicles := preload("res://scripts/sim/vehicles.gd")
## How close (tiles) a person must be to a container's spot to search it, and to a downed friend to help.
const REACH := 0.9
## The squad is out when each living member is within this of the exit's centre (or inside its rectangle).
const OUT_SLACK := 0.5

var sim
var site: Dictionary
var squad: Array = []
var containers: Array = []
var events: Array = []
var log: Array = []
var elapsed := 0.0
var carried := {}
var phase := "play"    # "play", "retreat", "ended"
var vehicle_kind := ""
var loot_mult := 1.0
var _ammo_start := 0.0
var _sleeping := {}
var _searching := {}    # person id -> container id
var _helping := {}      # person id -> {"who": person id, "t": seconds}
var _bitten := {}
var _total_dead_at_start := 0
var _survivor := false
var _hunted_by := {}


## `world` is the World node built from `site.data`; `squad_defs` the colony people's defs with their current state
## ({"def", "hp", "skills"} each, see `squad_of`); `ammo` the colony's ammunition they may use.
func _init(the_site: Dictionary, the_world, fx, members: Array, ammo: float, vehicle: String = "", mult: float = 1.0, has_survivor: bool = false) -> void:
	site = the_site
	vehicle_kind = vehicle
	loot_mult = mult
	_survivor = has_survivor
	sim = RaidSim.new(site.data, the_world, fx)
	sim.phase = "day"
	sim.stock.ammo = ammo
	_ammo_start = ammo
	var entry: Vector2 = site.entry
	var i := 0
	for m in members:
		var p = sim.add_person(m.def)
		p.skills = m.skills.duplicate()
		p.hp = float(m.hp)
		var spread := Vector2(float(i) - float(members.size() - 1) / 2.0, 0.0) * 0.9
		var at: Vector2 = entry + spread
		p.x = at.x
		p.y = at.y
		p.drafted = true
		p.activity = "In the raid"
		p.path = []
		squad.append(p)
		i += 1
	# nobody has a job or a chore here: left alone the squad stays where it stands (not off to a seat of the yard)
	sim.jobs.clear()
	sim.tactics.chores = false
	for c in site.containers:
		var d: Dictionary = c.duplicate(true)
		d["progress"] = 0.0
		d["looted"] = false
		var mult_loot := {}
		for k in d.get("loot", {}):
			mult_loot[k] = int(roundf(float(d.loot[k]) * loot_mult))
		d["loot"] = mult_loot
		containers.append(d)
	if _survivor:
		_add_survivor_spot()
	for z in site.dead:
		var zz = sim.spawn(float(z.pos.x), float(z.pos.y), "wander", String(z.get("kind", "walker")))
		if String(z.get("state", "still")) == "still":
			_sleeping[zz] = true
	_total_dead_at_start = site.dead.size()
	sim.events.clear()


## The squad's members as the run takes them: a colony person's def and their health and skills now.
static func squad_of(people: Array) -> Array:
	var out: Array = []
	for p in people:
		out.append({"def": p.def, "hp": p.hp, "skills": p.skills})
	return out


## Capacity of the squad's bags now (the living, and the vehicle's room).
func capacity() -> int:
	var n := 0
	for p in squad:
		if not p.dead and not p.downed:
			n += CARRY
	return n + (roundi(float(VEHICLE_CARRY) * Vehicles.cargo_of(vehicle_kind)) if vehicle_kind != "" else 0)


func carried_total() -> int:
	var n := 0
	for k in carried:
		n += int(carried[k])
	return n


## The container this person is searching now ("" when none), and the friend they are helping up (null when none).
func searching_of(p) -> String:
	return String(_searching.get(String(p.id), ""))


func helping_of(p):
	var h: Dictionary = _helping.get(String(p.id), {})
	return person(String(h.get("who", ""))) if not h.is_empty() else null


func container(id: String) -> Dictionary:
	for c in containers:
		if String(c.id) == id:
			return c
	return {}


func person(id: String):
	for p in squad:
		if String(p.id) == id:
			return p
	return null


func living() -> Array:
	var out: Array = []
	for p in squad:
		if not p.dead and not p.downed:
			out.append(p)
	return out


func dead_left() -> int:
	var n := 0
	for z in sim.zombies:
		if z.state != "dying" and z.state != "dead":
			n += 1
	return n


## The survivor of a place is somewhere far in: at the container farthest from the entry (one more thing to search).
func _add_survivor_spot() -> void:
	var best = null
	var best_d := -1.0
	for c in containers:
		var d: float = Vector2(c.pos).distance_to(Vector2(site.entry))
		if d > best_d:
			best_d = d
			best = c
	if best == null:
		return
	var spot: Vector2 = _free_spot_near(Vector2(best.pos))
	containers.append({"id": "survivor", "pos": spot, "at": spot, "kind": "survivor", "loot": {}, "search_s": 6.0, "room": String(best.get("room", "")), "progress": 0.0, "looted": false})


## An open tile near a point that is not on another container's spot (the survivor stands beside the place, not in it).
func _free_spot_near(at: Vector2) -> Vector2:
	var home_region: int = sim.region_at(at.x, at.y)
	for r in [1.2, 1.7, 2.3, 3.0]:
		for i in 12:
			var a := TAU * float(i) / 12.0
			var cand := at + Vector2(cos(a), sin(a)) * float(r)
			if sim.world.is_solid(sim.world.solid_p, cand.x, cand.y) or sim.region_at(cand.x, cand.y) != home_region:
				continue
			var clash := false
			for c in containers:
				if Vector2(c.pos).distance_to(cand) < 0.9:
					clash = true
			if not clash:
				return Vector2(floorf(cand.x) + 0.5, floorf(cand.y) + 0.5)
	return at


# --------------------------------------------------------------------- orders --

func order_move(p, tile: Vector2) -> bool:
	if phase != "play" or p == null or p.dead or p.downed:
		return false
	var ok: bool = sim.order_move(p, tile.x, tile.y)
	if ok:
		_searching.erase(String(p.id))
		_helping.erase(String(p.id))
	return ok


func order_search(p, container_id: String) -> bool:
	var c := container(container_id)
	if phase != "play" or p == null or p.dead or p.downed or c.is_empty() or bool(c.looted):
		return false
	if not sim.order_move(p, float(c.pos.x), float(c.pos.y)):
		return false
	_helping.erase(String(p.id))
	_searching[String(p.id)] = container_id
	return true


func order_help(p, friend) -> bool:
	if phase != "play" or p == null or friend == null or p == friend or p.dead or p.downed or not friend.downed or friend.dead:
		return false
	# beside them, on whichever side is open (a friend down against a wall)
	for off in [Vector2(0.8, 0.0), Vector2(-0.8, 0.0), Vector2(0.0, 0.8), Vector2(0.0, -0.8)]:
		if sim.order_move(p, friend.x + off.x, friend.y + off.y):
			_searching.erase(String(p.id))
			_helping[String(p.id)] = {"who": String(friend.id), "t": 0.0}
			return true
	return false


func retreat() -> void:
	if phase == "ended":
		return
	phase = "retreat"
	_searching.clear()
	_helping.clear()
	var ex: Rect2 = site.exit
	var centre := ex.get_center()
	var i := 0
	for p in squad:
		if p.dead or p.downed:
			continue
		var at := centre + Vector2(float(i % 3) - 1.0, float(i / 3) * 0.8) * 0.7
		sim.order_move(p, at.x, at.y)
		i += 1


# --------------------------------------------------------------------- the step --

func update(dt: float) -> void:
	if phase == "ended":
		return
	elapsed += dt
	for p in squad:
		if not p.dead and not p.downed:
			p.drafted = true    # (the squad always fights: being helped up or ordered about does not stand it down)
	_wake_the_dead()
	for p in squad:
		_search_step(p, dt)
		_help_step(p, dt)
	# the rules: the people, the dead, the crowd
	sim.t += dt
	for p in sim.people:
		sim._update_person(p, dt)
	for z in sim.zombies:
		if _sleeping.has(z):
			if z.state != "dying" and z.state != "dead":
				continue
			_sleeping.erase(z)    # (shot in its sleep: it falls like the others)
		sim._update_zombie(z, dt)
	sim._separate()
	var kept: Array = []
	for z in sim.zombies:
		if not z.remove:
			kept.append(z)
		else:
			_sleeping.erase(z)
	sim.zombies = kept
	_collect_events()
	_check_end()


func _wake_the_dead() -> void:
	var alive := living()
	if alive.is_empty():
		return
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "hunt" or z.state == "retreat":
			continue
		var seen = _first_seen(z, alive)
		if seen != null:
			_sleeping.erase(z)
			z.state = "hunt"
			z.hunt_id = String(seen.id)
			z.path = []
			z.repath = 0.0


func _first_seen(z, alive: Array):
	var best = null
	var best_d := NOTICE_R
	for p in alive:
		var d := Vector2(p.x - z.x, p.y - z.y).length()
		if d < best_d and sim.path_z.sight(sim.world.solid_z, Vector2(z.x, z.y), Vector2(p.x, p.y), 0.15):
			best_d = d
			best = p
	return best


## The shots heard: the dead near enough wake and hunt the nearest of the squad.
func _noise(at: Vector2) -> void:
	var alive := living()
	if alive.is_empty():
		return
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "hunt" or z.state == "retreat":
			continue
		if Vector2(z.x - at.x, z.y - at.y).length() > NOISE_R:
			continue
		var near = null
		var near_d := INF
		for p in alive:
			var d := Vector2(p.x - z.x, p.y - z.y).length()
			if d < near_d:
				near_d = d
				near = p
		if near != null:
			_sleeping.erase(z)
			z.state = "hunt"
			z.hunt_id = String(near.id)
			z.path = []
			z.repath = 0.0


func _search_step(p, dt: float) -> void:
	var cid: String = String(_searching.get(String(p.id), ""))
	if cid == "" or p.dead or p.downed:
		return
	var c := container(cid)
	if c.is_empty() or bool(c.looted):
		_searching.erase(String(p.id))
		return
	if p.moving or Vector2(p.x, p.y).distance_to(Vector2(c.pos)) > REACH:
		return
	c["progress"] = float(c.progress) + dt
	p.activity = "Searching"
	if float(c.progress) >= float(c.search_s):
		_open(p, c)
		_searching.erase(String(p.id))
		p.activity = "In the raid"


func _open(p, c: Dictionary) -> void:
	c["looted"] = true
	if String(c.kind) == "survivor":
		log.append("%s found someone alive and got them moving." % p.first)
		events.append({"type": "survivor", "id": String(c.id)})
		return
	var room: int = capacity() - carried_total()
	var took: Array = []
	var left := {}
	for k in c.loot:
		var n: int = int(c.loot[k])
		if n <= 0:
			continue
		var fit: int = mini(n, maxi(0, room))
		if fit > 0:
			carried[k] = int(carried.get(k, 0)) + fit
			room -= fit
			took.append("%d %s" % [fit, "med" if k == "meds" and fit == 1 else k])
		if fit < n:
			left[k] = n - fit
	if took.is_empty() and left.is_empty():
		log.append("%s found the %s empty." % [p.first, String(c.kind)])
	elif left.is_empty():
		log.append("%s searched the %s: %s." % [p.first, String(c.kind), ", ".join(took)])
	else:
		c["looted"] = false
		c["loot"] = left
		c["progress"] = 0.0
		log.append("%s took %s from the %s; the bags are full, some is left." % [p.first, ", ".join(took) if not took.is_empty() else "nothing", String(c.kind)])
	events.append({"type": "searched", "id": String(c.id)})


func _help_step(p, dt: float) -> void:
	var h: Dictionary = _helping.get(String(p.id), {})
	if h.is_empty() or p.dead or p.downed:
		return
	var friend = person(String(h.who))
	if friend == null or friend.dead or not friend.downed:
		_helping.erase(String(p.id))
		return
	if p.moving or Vector2(p.x, p.y).distance_to(Vector2(friend.x, friend.y)) > REACH + 0.6:
		return
	h["t"] = float(h.t) + dt
	if float(h.t) >= HELP_S:
		friend.downed = false
		friend.drafted = true
		friend.hp = GET_UP_HP
		friend.bleed_out = -1.0
		friend.stabilised = false
		_helping.erase(String(p.id))
		log.append("%s got %s back on their feet." % [p.first, friend.first])


func _collect_events() -> void:
	for e in sim.events:
		var t := String(e.get("type", ""))
		if t == "shot":
			_noise(Vector2(float(e.x), float(e.y)))
		elif t == "bite":
			var who = person(String(e.get("who", "")))
			if who != null and not _bitten.has(String(who.id)):
				_bitten[String(who.id)] = true
				log.append("%s was bitten." % who.first)
		events.append(e)
	sim.events.clear()
	# a friend brought down
	for p in squad:
		if p.downed and not _bitten.has(String(p.id)):
			_bitten[String(p.id)] = true


func _check_end() -> void:
	var alive := living()
	if alive.is_empty():
		phase = "ended"
		return
	if phase != "retreat":
		return
	var ex: Rect2 = site.exit
	for p in alive:
		if not ex.grow(OUT_SLACK).has_point(Vector2(p.x, p.y)):
			return
	phase = "ended"


func finished() -> bool:
	return phase == "ended"


## The trip's result in the dice's format: {"loot", "hurt", "lost", "clear", "rescue", "beats", "ammo_used"}.
## A person down at the end is lost.
func result() -> Dictionary:
	var hurt := {}
	var lost: Array = []
	for p in squad:
		if p.dead or p.downed:
			lost.append(String(p.id))
		elif _bitten.has(String(p.id)):
			hurt[String(p.id)] = "bite"
	var came := lost.size() < squad.size()
	var loot := {}
	if came:
		for k in carried:
			if int(carried[k]) > 0:
				loot[String(k)] = int(carried[k])
	var out := {"loot": loot, "hurt": hurt, "lost": lost}
	var left := dead_left()
	if came and left <= maxi(1, int(_total_dead_at_start / 8)):
		out["clear"] = true
	if came and _survivor and bool(container("survivor").get("looted", false)):
		out["rescue"] = true
	out["ammo_used"] = maxf(0.0, _ammo_start - float(sim.stock.ammo))
	out["beats"] = log.slice(maxi(0, log.size() - 3))
	return out
