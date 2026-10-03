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
##
## THE AVATAR (round 17, slice 1). With a player (`set_player`) the person they play walks, aims and shoots by their own hands
## (`sim.avatar`: set_input, reload, melee: avatar.gd) and is never ordered about; they search by standing at a container
## (`begin_search`, `stop_search`) and get a friend up by standing beside them (`begin_help`). The other people are the squad
## (scripts/raid/squad_ai.gd): they follow the player by default, and what the player asks of them over the radio (`request`:
## come, hold, cover, search that, go back) is a stance they keep and shoot from. The old orders (`order_move`, `order_search`,
## `order_help`, `retreat`) still work for everyone but the player, and a squad with no player is the old squad. When the avatar
## falls the next of the squad leads (`on_avatar_down`, which `update` calls by itself): the base's `finish_played` is told in
## `result()` who was lost, and who leads. `result()` carries what the base needs: `hp`, `skills` and `trust_delta` besides the
## trip's own keys. The place has the base's clock (`mirror`, `hour`).
extends RefCounted

const RaidSim := preload("res://scripts/raid/raid_sim.gd")
const SquadAI := preload("res://scripts/raid/squad_ai.gd")

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
## What a person who came home having followed the whole way is worth in trust (the radio's `TRIP_BONUS`).
const TRIP_TRUST := 2.0
## A point is on a container's furniture if it is within this of its footprint (tiles); a stand-at spot, within this.
const CONTAINER_SLACK := 0.35
const SPOT_R := 0.8

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
## The squad's own AI (scripts/raid/squad_ai.gd), what each person's skills and health were when they came, who has been down.
var squad_ai
var _skills_start := {}
var _ever_down := {}
var _footprints := {}


## `world` is the World node built from `site.data`; `squad_defs` the colony people's defs with their current state
## ({"def", "hp", "skills", "trust"} each, see `squad_of`); `ammo` the colony's ammunition they may use.
func _init(the_site: Dictionary, the_world, fx, members: Array, ammo: float, vehicle: String = "", mult: float = 1.0, has_survivor: bool = false) -> void:
	site = the_site
	vehicle_kind = vehicle
	loot_mult = mult
	_survivor = has_survivor
	sim = RaidSim.new(site.data, the_world, fx)
	sim.phase = "day"
	# (a place with nothing to mirror is a morning: the scene gives it the base's clock with `mirror`)
	sim.minutes = 10.0 * 60.0
	sim.stock.ammo = ammo
	_ammo_start = ammo
	var entry: Vector2 = site.entry
	var i := 0
	for m in members:
		var p = sim.add_person(m.def)
		p.skills = m.skills.duplicate()
		_skills_start[String(p.id)] = p.skills.duplicate()
		p.hp = float(m.hp)
		p.trust = clampf(float(m.get("trust", 55.0)), 0.0, 100.0)
		p.stance = ""
		p.stance_at = Vector2.ZERO
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
	# the squad's AI: the people with a stance are told where to be by it, and the radio hands it the stances that take effect
	squad_ai = SquadAI.new(self)
	sim.squad_goal = squad_ai.goal_for
	sim.radio.on_applied = squad_ai.applied


## The squad's members as the run takes them: a colony person's def and their health, skills and trust in the player now.
static func squad_of(people: Array) -> Array:
	var out: Array = []
	for p in people:
		out.append({"def": p.def, "hp": p.hp, "skills": p.skills, "trust": p.trust})
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


# ----------------------------------------------------------------- the avatar --

## Makes this member of the squad the player (null gives the avatar up). False, and nothing changes, for someone who is not in
## the squad, is down or gone. The others who have no stance follow them from now on.
func set_player(p) -> bool:
	if p == null:
		return sim.avatar.set_player(null)
	if not squad.has(p) or p.dead or p.downed or p.turned:
		return false
	if not sim.avatar.set_player(p):
		return false
	_searching.erase(String(p.id))
	_helping.erase(String(p.id))
	for q in squad:
		if q != p and not q.dead and not q.downed and q.order == null and String(q.stance) == "":
			sim.radio.set_stance(q, "follow")
	return true


## The player's hands for the coming steps (the scene calls it every frame): the way to walk (any length), the point of the
## place in tiles the mouse is over, and whether the trigger is held. Once the trip is over the hands are let go.
func set_input(move: Vector2, aim: Vector2, fire: bool) -> void:
	if phase == "ended":
		sim.avatar.set_input(Vector2.ZERO, aim, false)
	else:
		sim.avatar.set_input(move, aim, fire)


## The reload key and the melee key (`Avatar.reload`, `Avatar.melee`): false when there is no player or the trip is over.
func reload() -> bool:
	return phase != "ended" and sim.avatar.reload()


func melee() -> bool:
	return phase != "ended" and sim.avatar.melee()


## The person the player controls (the leader), or null (nobody is, or they are not of the squad).
func avatar():
	var p = sim.avatar.player()
	return p if p != null and squad.has(p) else null


func leader():
	return avatar()


## The base's clock in the place (the scene calls `mirror(colony)` every step or frame), for the dead and for the light.
func mirror(colony) -> void:
	sim.mirror(colony)


## The hour of the day in the place, 0 up to 24 (the base's, once mirrored: a place with none is a morning).
func hour() -> float:
	return float(sim.hour)


func is_night() -> bool:
	return sim.is_night()


## The avatar went down (or died, or turned): the next of the squad who can stand leads (the most trusted, then the best at
## Leading; everyone trusts the player ten less and a mourning goes through the mood, `Avatar.on_player_lost`). Returns whoever
## leads now: the same person while the avatar stands, the new leader, or null when nobody can stand (the run ends). `update`
## calls it each step; the scene may ask too (it changes nothing the second time).
func on_avatar_down():
	var p = avatar()
	if p == null:
		return null
	if not (p.dead or p.downed or p.turned):
		return p
	var heir = null
	for q in squad:
		if q != p and not q.dead and not q.downed and not q.turned:
			heir = q
			break
	if heir == null:
		return null
	_searching.erase(String(p.id))
	_helping.erase(String(p.id))
	sim.avatar.on_player_lost(p)
	var lead = avatar()
	if lead != null:
		_searching.erase(String(lead.id))
		_helping.erase(String(lead.id))
	return lead


# ------------------------------------------------------------------ by hand --

## The player (or anyone) starts searching a container: they must stand within REACH of its spot, nobody else may be on it,
## and a player must have their hands off the keys (walking, firing and swinging cancel a search). The search goes on while
## they stand there (`_search_step`); what was done stays in the container if they leave.
func begin_search(p, container_id: String) -> bool:
	var c := container(container_id)
	if phase != "play" or p == null or p.dead or p.downed or c.is_empty() or bool(c.looted):
		return false
	if Vector2(p.x, p.y).distance_to(Vector2(c.pos)) > REACH:
		return false
	var other = searcher_of(container_id)
	if other != null and other != p:
		return false
	if p.player and (p.input_move.length() > 0.1 or p.input_fire):
		return false
	_helping.erase(String(p.id))
	_searching[String(p.id)] = container_id
	return true


## Whether they were searching.
func stop_search(p) -> bool:
	return p != null and _searching.erase(String(p.id))


## Whoever is searching this container now (a person, or null).
func searcher_of(container_id: String):
	for id in _searching:
		if String(_searching[id]) == container_id:
			var who = person(String(id))
			if who != null and not who.dead and not who.downed:
				return who
	return null


## The player (or anyone) starts getting a downed friend up: they must stand within reach of them (REACH + 0.6); a player must
## have their hands off the keys. HELP_S seconds beside them and the friend is up on GET_UP_HP.
func begin_help(p, friend) -> bool:
	if phase != "play" or p == null or friend == null or p == friend or p.dead or p.downed or not friend.downed or friend.dead:
		return false
	if Vector2(p.x, p.y).distance_to(Vector2(friend.x, friend.y)) > REACH + 0.6:
		return false
	if p.player and (p.input_move.length() > 0.1 or p.input_fire):
		return false
	_searching.erase(String(p.id))
	_helping[String(p.id)] = {"who": String(friend.id), "t": 0.0}
	return true


func stop_help(p) -> bool:
	return p != null and _helping.erase(String(p.id))


## The containers within `r` tiles of `point` (the place to stand at to search it counts), nearest first: what the scene offers
## ("press E to search") and what a request resolves. A searched one is left out unless `only_open` is false.
func containers_near(point: Vector2, r: float, only_open: bool = true) -> Array:
	var hits: Array = []
	for c in containers:
		if only_open and bool(c.looted):
			continue
		var d := Vector2(c.pos).distance_to(point)
		if d <= r:
			hits.append({"d": d, "c": c})
	hits.sort_custom(func(a, b): return a.d < b.d)
	var out: Array = []
	for h in hits:
		out.append(h.c)
	return out


## The container a point of the place names: the one whose furniture the point is on (a little to spare), or whose spot to
## stand at it is next to; the nearest when there are two; {} when there is none. A searched one is named too (the caller
## says it is done).
func container_at(point: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for c in containers:
		var d := INF
		if _footprint(c).grow(CONTAINER_SLACK).has_point(point):
			d = Vector2(c.at).distance_to(point)
		var spot := Vector2(c.pos).distance_to(point)
		if spot <= SPOT_R:
			d = minf(d, spot)
		if d < best_d:
			best_d = d
			best = c
	return best


## The ground a container's furniture covers: its prop in the site's map when there is one, else a tile and a half round it.
func _footprint(c: Dictionary) -> Rect2:
	var id := String(c.id)
	if _footprints.has(id):
		return _footprints[id]
	var at := Vector2(c.at)
	var r := Rect2(at - Vector2(0.75, 0.75), Vector2(1.5, 1.5))
	for o in site.data.get("objects", []):
		if o.has("cx") and o.has("w") and o.has("h") and absf(float(o.cx) - at.x) < 0.01 and absf(float(o.cy) - at.y) < 0.01:
			var size := Vector2(float(o.w), float(o.h))
			r = Rect2(at - size * 0.5, size)
			break
	_footprints[id] = r
	return r


# ---------------------------------------------------------------- the radio --

## Asks somebody of the squad (the person, or their id) over the radio: the radio's `request` (willingness, trust, the delay and
## the line) with what a place adds: "search" takes the point `args.at` (or where the player aims) to a container ("Nothing to
## search there", "Already searched", "Somebody is already on it"), "hold" a point they can walk to ("Dez: can't get there"),
## and there are no walls to man ("post"); when the trip is turning back nothing is asked. Returns the radio's {"ok", "line", "why", "delay_s", "tone", "insisted"}.
func request(contact, verb: String, args: Dictionary = {}) -> Dictionary:
	var p = person(String(contact)) if typeof(contact) == TYPE_STRING else contact
	if p == null or not squad.has(p):
		return _refusal("Nobody answers")
	if phase != "play":
		return _refusal("We are heading out")
	if verb == "post":
		return _refusal("%s: there are no walls to man out here" % String(p.first))
	var a: Dictionary = args.duplicate()
	if verb == "hold" and typeof(a.get("at", null)) == TYPE_VECTOR2:
		var spot = squad_ai.hold_spot(p, Vector2(a.at))
		if spot == null:
			return _refusal("%s: can't get there" % String(p.first))
		a["at"] = Vector2(spot)
	if verb == "search" and not bool(sim.radio.willingness(p, verb).get("hard", false)):
		var at = a.get("at", null)
		if typeof(at) != TYPE_VECTOR2:
			var lead = avatar()
			at = Vector2(lead.input_aim) if lead != null and lead.input_aim != Vector2.ZERO else Vector2(p.x, p.y)
		var c := container_at(Vector2(at))
		if c.is_empty():
			return _refusal("Nothing to search there")
		if bool(c.looted):
			return _refusal("Already searched")
		var other = searcher_of(String(c.id))
		if other != null and other != p:
			return _refusal("Somebody is already on it")
		a["at"] = Vector2(c.pos)
	return sim.radio.request(p, verb, a)


func _refusal(why: String) -> Dictionary:
	return {"ok": false, "line": "", "why": why, "delay_s": 0.0, "tone": "refused", "insisted": false}


# --------------------------------------------------------------------- orders --

func order_move(p, tile: Vector2) -> bool:
	if phase != "play" or p == null or p.dead or p.downed:
		return false
	var ok: bool = sim.order_move(p, tile.x, tile.y)
	if ok:
		_searching.erase(String(p.id))
		_helping.erase(String(p.id))
		_drop_stance(p)
	return ok


func order_search(p, container_id: String) -> bool:
	var c := container(container_id)
	if phase != "play" or p == null or p.dead or p.downed or c.is_empty() or bool(c.looted):
		return false
	if not sim.order_move(p, float(c.pos.x), float(c.pos.y)):
		return false
	_helping.erase(String(p.id))
	_searching[String(p.id)] = container_id
	_drop_stance(p)
	return true


func order_help(p, friend) -> bool:
	if phase != "play" or p == null or friend == null or p == friend or p.dead or p.downed or not friend.downed or friend.dead:
		return false
	# beside them, on whichever side is open (a friend down against a wall)
	for off in [Vector2(0.8, 0.0), Vector2(-0.8, 0.0), Vector2(0.0, 0.8), Vector2(0.0, -0.8)]:
		if sim.order_move(p, friend.x + off.x, friend.y + off.y):
			_searching.erase(String(p.id))
			_helping[String(p.id)] = {"who": String(friend.id), "t": 0.0}
			_drop_stance(p)
			return true
	return false


## An order of the old kind replaces what the radio asked of a person (and any such request still waiting).
func _drop_stance(p) -> void:
	p.stance = ""
	p.stance_at = Vector2.ZERO
	var i: int = sim.radio.pending.size() - 1
	while i >= 0:
		if String(sim.radio.pending[i].who) == String(p.id):
			sim.radio.pending.remove_at(i)
		i -= 1


## Turns back: everyone but the player walks to the exit (the player walks there by hand), and the run is over when each of
## the living is in it.
func retreat() -> void:
	if phase == "ended":
		return
	phase = "retreat"
	_searching.clear()
	_helping.clear()
	var i := 0
	for p in squad:
		if p.dead or p.downed or p.player:
			continue
		_order_out_at(p, i)
		i += 1


## One person is sent to the exit now (somebody whose request took effect as the trip turned back).
func order_out(p) -> void:
	if p == null or p.dead or p.downed or p.player:
		return
	_order_out_at(p, maxi(0, squad.find(p)))


func _order_out_at(p, i: int) -> void:
	var centre: Vector2 = Rect2(site.exit).get_center()
	var at := centre + Vector2(float(i % 3) - 1.0, float(i / 3) * 0.8) * 0.7
	sim.order_move(p, at.x, at.y)


# --------------------------------------------------------------------- the step --

func update(dt: float) -> void:
	if phase == "ended":
		return
	elapsed += dt
	sim.radio.tick(dt)    # (the place does not run `Sim.update`: the requests' delays and the stances that end are the radio's)
	for p in squad:
		if not p.dead and not p.downed and not p.player:
			p.drafted = true    # (the squad always fights: being helped up or ordered about does not stand it down)
	squad_ai.step(dt)
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
	on_avatar_down()    # (before the events are collected: the scene gets the succession in the step it happened)
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
	var far: bool = Vector2(p.x, p.y).distance_to(Vector2(c.pos)) > REACH
	if p.player:
		# the player's own hands end it: walking off, firing, swinging
		if far or p.input_move.length() > 0.1 or p.input_fire or p.input_melee:
			_searching.erase(String(p.id))
			return
	elif p.moving or far:
		return
	elif squad_ai.active() and squad_ai.engaged(p):
		return    # (somebody who has a target in their sights is shooting, not searching)
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
	var far: bool = Vector2(p.x, p.y).distance_to(Vector2(friend.x, friend.y)) > REACH + 0.6
	if p.player:
		if far or p.input_move.length() > 0.1 or p.input_fire or p.input_melee:
			_helping.erase(String(p.id))
			return
	elif p.moving or far:
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
		if p.downed:
			_ever_down[String(p.id)] = true
			if not _bitten.has(String(p.id)):
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


## The trip's result in the dice's format: {"loot", "hurt", "lost", "clear", "rescue", "beats", "ammo_used"}, and what the base
## needs of a played one: `hp` {person id: health they leave with} and `skills` {person id: {skill: points gained here, at most
## three, never Leading}} for every member who comes home (`finish_played` puts them in), `trust_delta` {person id: n} (what
## the trip is worth in the base's trust in the player: TRIP_TRUST for someone who came home standing, was never down and was
## with the player to the end, not left holding or waiting; 0 otherwise or with no player; the base's own
## `radio.on_trip_led` gives the same bonus: use one of the two) and `leader` (the id of the person the player controlled when it
## ended, with a player). A person down at the end, or dead, is lost.
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
	var hp := {}
	var skills := {}
	var trust := {}
	var lead = avatar()
	for p in squad:
		var id := String(p.id)
		if p.dead or p.downed:
			trust[id] = 0.0
			continue
		hp[id] = clampf(float(p.hp), 0.0, 100.0)
		var gain := {}
		var was: Dictionary = _skills_start.get(id, p.skills)
		for k in sim.skills.SKILLS:
			if sim.skills.NO_GROWTH.has(k):
				continue
			var n := int(p.skills.get(k, 0)) - int(was.get(k, 0))
			if n > 0:
				gain[String(k)] = mini(n, int(sim.skills.MAX_GAIN))
		if not gain.is_empty():
			skills[id] = gain
		trust[id] = TRIP_TRUST if lead != null and p != lead and not _ever_down.has(id) and String(p.stance) != "hold" and String(p.stance) != "back" else 0.0
	out["hp"] = hp
	out["skills"] = skills
	out["trust_delta"] = trust
	if lead != null:
		out["leader"] = String(lead.id)
	return out
