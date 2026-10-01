## The simulation: the clock, the six people, the dead, and the wall.
## Everything is in tile units; one tile is roughly a metre.
extends RefCounted

const Pathfinder := preload("res://scripts/sim/pathfinder.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")
const Scenario := preload("res://scripts/sim/scenario.gd")
const Waves := preload("res://scripts/sim/waves.gd")

## What a new run starts with (tuned later with the balance harness). Food and
## water are six days of full rations for the crew of six (6 x 1 x 6 food, 6 x
## 1.5 x 6 water): with no income the first person is hungry or thirsty on day 7.
const START_STOCK := {"ammo": 300.0, "scrap": 30.0, "food": 36.0, "water": 54.0, "meds": 10.0}
## The story, standard and brutal difficulties.
const DIFFICULTY_NAMES := ["Story", "Standard", "Brutal"]

## What one shot costs from the stock of ammo (a shotgun shell is a bigger share).
const SHOT_COST := 0.2
const SHELL_COST := 0.34
## The school's two north doors are wall sections of this kind. The building is
## shut to the dead until one is broken (see `refresh_school`).
const DOOR_KIND := "door"
## The school's tiles start at this row (its north wall).
const SCHOOL_TOP_ROW := 44
## The most of the dead sent back to the city in one step at dawn (each one is a
## path search).
const DAWN_LEAVES_PER_STEP := 6
## What someone fights with when the stock cannot pay for another shot: the butt
## of their gun.
const BUTT := {"name": "Butt of the gun", "range": 1.9, "cooldown": 1.25, "melee": true, "dmg": 1.1, "acc": 0.7}

const PIVOT := {"S": Vector2(-0.04, -0.08), "E": Vector2(0.08, -0.14), "N": Vector2(0.26, -0.22)}


class Slot:
	extends RefCounted
	var x: float
	var y: float
	var ax: float
	var ay: float
	var face: String
	var who = null
	var seg = null


class Segment:
	extends RefCounted
	var id: int
	var kind: String
	var side: String
	var from: float
	var to: float
	var name: String
	var hp: float
	var max_hp: float
	var state := 0
	var tiles: Array = []
	var center := Vector2.ZERO
	var slots: Array = []
	var obj: Dictionary


class Person:
	extends RefCounted
	var def: Dictionary
	var id: String
	var name: String
	var first: String
	var look: Dictionary
	var weapon: String
	var gun: Dictionary
	var x: float
	var y: float
	var facing := "S"
	var hp := 100.0
	var mag := 0
	var cooldown := 0.0
	var reloading := 0.0
	var aim := 0.0
	var target = null
	var path: Array = []
	var path_i := 0
	var goal_key := ""
	var moving := false
	var walk_phase := 0.0
	var drafted := false
	var order = null
	var repair = null
	var activity := ""
	var recoil := 0.0
	var thrust := 0.0
	var downed := false
	var hammer_t := 0.0
	## Died (bled out, starved...) or turned: out of the game for good.
	var dead := false
	var turned := false
	## Game hours since they last ate a proper meal or drank.
	var hunger_h := 0.0
	var thirst_h := 0.0
	## Health lost per game hour from open wounds, and how many wounds are open.
	var bleeding := 0.0
	var wounds := 0
	## Game hours left to be stabilised while downed, or -1 when that does not apply.
	var bleed_out := -1.0
	var stabilised := false
	## When (in sim.clock_min game minutes) they were infected and will turn, or -1.
	var infected_at := -1.0
	var turn_at := -1.0
	## Where they are healing in bed (a Vector2), or null.
	var resting_bed = null
	## The scavenging party they are away with (they are off the map), or null.
	var away = null


class Zombie:
	extends RefCounted
	var x: float
	var y: float
	var look: Dictionary
	var look_index := 0
	var state: String
	var hp: float
	var speed: float
	var limp: bool
	var facing := "S"
	var moving := false
	var walk_phase := 0.0
	var t := 0.0
	var path: Array = []
	var path_i := 0
	var slot = null
	var attack_t := 0.0
	var stagger := 0.0
	var fall := 0.0
	var fall_dir := 1.0
	var groan_t := 0.0
	var repath := 0.0
	var wander_t := 0.0
	var dead_t := 0.0
	var remove := false
	## The name of the survivor this used to be, for one who turned.
	var turned_name := ""


var world
var fx
var d: Dictionary
var W: int
var H: int
var path_z
var path_p
var minutes := 18.0 * 60.0 + 46.0
## Game minutes since the run began (never wraps at midnight), for timers.
var clock_min := 0.0
var min_per_sec := 3.0
var day := 3
var phase := "day"
var t := 0.0
var people: Array = []
var zombies: Array = []
var looks: Array = []
var segments: Array = []
var events: Array = []
var alerts := {}
var bell_rung := false
var spawn_t := 6.0
var kills := 0
var stock := {"ammo": 212.0, "scrap": 24.0, "food": 41.0, "water": 230.0, "meds": 7.0}
var on_segment_change: Callable
var spawns: Array = []
var guns: Dictionary
var weapons: Dictionary
## The one random source of the rules, seeded per run.
var rng := RandomNumberGenerator.new()
var run_seed := 0
## 0 story, 1 standard, 2 brutal.
var difficulty := 1
## Whether a person who bleeds out dies for good.
var permadeath := true
## "clear" or "rain" (set each dawn by the supplies module).
var weather := "clear"
## "" while the run goes on, then "defeat" or "victory". The rules stop stepping.
var over := ""
var supplies
var medical
var scavenge
var scenario
var waves
## Whether the school's inside is open to the dead right now: a door is down or one
## of the dead is already in there.
var school_open := false
var _school_inner: Array = []


func _init(data: Dictionary, w, effects) -> void:
	d = data
	world = w
	fx = effects
	W = int(d.W)
	H = int(d.H)
	min_per_sec = float(d.minPerSec)
	guns = d.guns
	weapons = d.weapons
	path_z = Pathfinder.new(W, H, world.solid_z)
	path_p = Pathfinder.new(W, H, world.solid_p)
	phase = phase_at(minutes)
	looks = d.zombieLooks
	for sp in d.spawns:
		spawns.append(Vector2(sp[0], sp[1]))
	for s in d.segments:
		var seg := Segment.new()
		seg.id = int(s.id)
		seg.kind = s.kind
		seg.side = s.side
		seg.from = s.from
		seg.to = s.to
		seg.name = s.name
		seg.hp = s.hp
		seg.max_hp = s.hp
		seg.tiles = s.tiles
		seg.center = Vector2(s.center.x, s.center.y)
		seg.obj = d.objects[_object_index(int(s.obj))]
		for sl in s.slots:
			var slot := Slot.new()
			slot.x = sl.x
			slot.y = sl.y
			slot.ax = sl.ax
			slot.ay = sl.ay
			slot.face = sl.face
			slot.seg = seg
			seg.slots.append(slot)
		segments.append(seg)
	var door_tiles := {}
	for seg in segments:
		if seg.kind == DOOR_KIND:
			for i in seg.tiles:
				door_tiles[int(i)] = true
	for i in W * H:
		@warning_ignore("integer_division")
		if int(d.solidZ[i]) == 1 and int(d.solidP[i]) == 0 and i / W >= SCHOOL_TOP_ROW and not door_tiles.has(i):
			_school_inner.append(i)
	for def in d.people:
		people.append(_make_person(def))
	supplies = Supplies.new()
	medical = Medical.new()
	scavenge = Scavenge.new()
	scenario = Scenario.new()
	waves = Waves.new()
	for m in [supplies, medical, scavenge, scenario, waves]:
		m.setup(self)
	_seed()


func _object_index(id: int) -> int:
	for i in d.objects.size():
		if int(d.objects[i].id) == id:
			return i
	return 0


func _make_person(def: Dictionary) -> Person:
	var p := Person.new()
	p.def = def
	p.id = def.id
	p.name = def.name
	p.first = def.name.split(" ")[0]
	p.look = def.look
	p.weapon = def.weapon
	p.gun = weapons[def.weapon]
	p.x = def.job.x
	p.y = def.job.y
	p.mag = int(p.gun.get("mag", 0))
	p.cooldown = rng.randf()
	p.aim = guns[def.weapon].rest
	p.walk_phase = rng.randf() * 6.0
	p.activity = def.job.what
	return p


var hour: float:
	get:
		return fmod(minutes / 60.0, 24.0)


static func phase_at(mins: float) -> String:
	var h := fmod(mins / 60.0, 24.0)
	if h >= 19.0 and h < 20.5:
		return "dusk"
	if h >= 20.5 or h < 5.5:
		return "night"
	if h < 6.5:
		return "dawn"
	return "day"


static func facing_of(dx: float, dy: float, prev: String = "") -> String:
	var ax := absf(dx)
	var ay := absf(dy)
	if (prev == "E" or prev == "W") and ax > ay * 0.8:
		return "E" if dx > 0 else "W"
	if (prev == "N" or prev == "S") and ay > ax * 0.8:
		return "S" if dy > 0 else "N"
	if ax > ay:
		return "E" if dx > 0 else "W"
	return "S" if dy > 0 else "N"


static func ang_diff(a: float, b: float) -> float:
	return atan2(sin(b - a), cos(b - a))


func _seed() -> void:
	for pair in [[1, 1], [2, 1], [2, 4], [7, 1], [11, 2], [0, 6]]:
		var sl: Slot = segments[pair[0]].slots[pair[1]]
		var z := spawn(sl.x, sl.y, "attack")
		z.slot = sl
		sl.who = z
		z.facing = sl.face
	for p in [[24, 9], [33.5, 11.4], [41, 7.4], [52, 10.2], [58.5, 8.4], [9, 27], [74.5, 27]]:
		spawn(p[0], p[1], "approach")
	for p in [[7.5, 47], [76.5, 45], [3.6, 8.6], [80, 8.2], [66, 7.2]]:
		spawn(p[0], p[1], "wander")


func spawn(x: float, y: float, state: String) -> Zombie:
	var z := Zombie.new()
	z.x = x
	z.y = y
	z.look_index = rng.randi() % looks.size()
	z.look = looks[z.look_index]
	z.state = state
	z.hp = 4 + rng.randi() % 4
	z.speed = 0.5 + rng.randf() * 0.35
	z.limp = rng.randf() < 0.4
	z.walk_phase = rng.randf() * 6.0
	z.t = rng.randf() * 10.0
	z.attack_t = rng.randf()
	z.groan_t = 2.0 + rng.randf() * 10.0
	zombies.append(z)
	return z


func alert(id: String, level: String, text: String, sub: String, at, ttl: float = 5.0) -> void:
	var born := t
	if alerts.has(id):
		born = alerts[id].born
	alerts[id] = {"id": id, "level": level, "text": text, "sub": sub, "at": at, "t": t, "ttl": ttl, "born": born}


# ------------------------------------------------------------------ orders --

func toggle_draft(p: Person) -> void:
	p.drafted = not p.drafted
	p.repair = null
	p.order = Vector3(p.x, p.y, 0) if p.drafted else null


func order_move(p: Person, x: float, y: float) -> bool:
	if p.downed or p.dead or p.away != null:
		return false
	if world.is_solid(world.solid_p, x, y):
		return false
	p.drafted = true
	p.repair = null
	p.order = Vector3(x, y, 0)
	p.goal_key = ""
	return true


func order_post(p: Person) -> void:
	p.drafted = true
	p.repair = null
	p.order = Vector3(p.def.post.x, p.def.post.y, 1)
	p.goal_key = ""


func order_repair(p: Person, seg: Segment) -> void:
	p.drafted = false
	p.order = null
	p.repair = seg
	p.goal_key = ""


## How well a person does things right now (shooting, repairing): 1.0 normal,
## less when hungry, thirsty or hurt.
func perf(p: Person) -> float:
	return supplies.perf(p) * medical.perf(p)


## Small status marks for a person's card and panel, from every module:
## [{"icon": String, "color": Color, "tip": String}].
func status_of(p: Person) -> Array:
	return supplies.status_of(p) + medical.status_of(p) + scavenge.status_of(p)


## Game hours that pass in `dt` seconds of the rules' time.
func game_hours(dt: float) -> float:
	return dt * min_per_sec / 60.0


## A button the HUD offers for the selection (see the modules' gizmo()):
## true if a module took it.
func handle_gizmo(id: String, sel) -> bool:
	for m in [medical, scavenge, supplies, scenario]:
		if m.has_method("gizmo") and m.gizmo(id, sel):
			return true
	return false


## Sets up a fresh run on a newly built Sim: day 1 at 07:00, the starting
## stocks, a quiet yard, the seed and difficulty.
func start_run(difficulty_index: int, seed_value: int) -> void:
	difficulty = clampi(difficulty_index, 0, 2)
	run_seed = seed_value
	rng.seed = seed_value
	# what _make_person rolled before the seed was set
	for p in people:
		p.cooldown = rng.randf()
		p.walk_phase = rng.randf() * 6.0
	day = 1
	minutes = 7.0 * 60.0
	clock_min = 0.0
	phase = phase_at(minutes)
	bell_rung = false
	spawn_t = 6.0
	kills = 0
	over = ""
	weather = "clear"
	stock = START_STOCK.duplicate()
	events.clear()
	alerts.clear()
	zombies.clear()
	for seg in segments:
		for sl in seg.slots:
			sl.who = null
	for pos in [[7.5, 47], [76.5, 45], [3.6, 8.6], [80, 8.2]]:
		spawn(pos[0], pos[1], "wander")
	for m in [supplies, medical, scavenge, scenario, waves]:
		m.start()


# ------------------------------------------------------------------ update --

func update(dt: float) -> void:
	if over != "":
		return
	t += dt
	var before := phase
	minutes += dt * min_per_sec
	clock_min += dt * min_per_sec
	if minutes >= 24.0 * 60.0:
		minutes -= 24.0 * 60.0
	phase = phase_at(minutes)
	var h := hour
	if not bell_rung and h >= 19.0 and h < 20.5:
		bell_rung = true
		events.append({"type": "bell"})
		events.append({"type": "banner", "text": "The bell rings", "sub": "Everyone to the wall"})
		alert("bell", "info", "The bell has rung", "Everyone is heading to their posts", null, 14.0)
	if before != phase:
		if phase == "night":
			events.append({"type": "banner", "text": "Night %d" % day, "sub": "Hold the wall until dawn"})
			alert("horde", "warn", "The dead are coming", "More walkers every hour until dawn", null, 12.0)
		elif phase == "dawn":
			events.append({"type": "banner", "text": "Dawn", "sub": "The dead drift back into the city"})
		elif phase == "day":
			day += 1
			bell_rung = false
			events.append({"type": "day_start", "day": day})
			events.append({"type": "banner", "text": "Day %d" % day, "sub": "Repair the wall before dusk"})

	scenario.update(dt)
	supplies.update(dt)
	medical.update(dt)
	scavenge.update(dt)
	waves.update(dt)

	if phase == "dawn":
		_dawn_sweep()
	for p in people:
		_update_person(p, dt)
	for z in zombies:
		_update_zombie(z, dt)
	refresh_school()
	_separate()
	var kept: Array = []
	for z in zombies:
		if not z.remove:
			kept.append(z)
	zombies = kept
	for id in alerts.keys():
		var a: Dictionary = alerts[id]
		if t - a.t > a.ttl:
			alerts.erase(id)


# ------------------------------------------------------------------ people --

func _goal_for(p: Person):
	if p.downed or p.dead or p.away != null:
		return null
	if p.order != null:
		var is_post: bool = p.order.z > 0.5
		return {"x": p.order.x, "y": p.order.y, "face": _post_face(p) if is_post else "", "what": p.def.post.what if is_post else "Holding position"}
	var duty = medical.goal_for(p)
	if duty == null:
		duty = scavenge.goal_for(p)
	if duty != null:
		return duty
	if p.repair != null:
		var s: Segment = p.repair
		return {"x": s.center.x, "y": s.center.y, "face": "N" if s.side == "S" else s.side, "what": "Repairing the %s" % s.name.to_lower()}
	var night := phase == "night" or phase == "dawn" or (phase == "dusk" and bell_rung)
	if night:
		return {"x": float(p.def.post.x), "y": float(p.def.post.y), "face": _post_face(p), "what": p.def.post.what}
	return {"x": float(p.def.job.x), "y": float(p.def.job.y), "face": "N" if p.id == "ruth" else "", "what": p.def.job.what}


func _post_face(p: Person) -> String:
	var x: float = p.def.post.x
	var y: float = p.def.post.y
	if x < 22.0:
		return "N" if y < 19.0 else "W"
	if x > 62.0:
		return "N" if y < 19.0 else "E"
	return "N"


func _update_person(p: Person, dt: float) -> void:
	p.recoil = maxf(0.0, p.recoil - dt * 8.0)
	p.thrust = maxf(0.0, p.thrust - dt * 4.0)
	if p.downed or p.dead or p.away != null:
		return
	var goal = _goal_for(p)
	if goal != null:
		p.activity = goal.what
		var key := "%.1f,%.1f" % [goal.x, goal.y]
		var dist := Vector2(goal.x - p.x, goal.y - p.y).length()
		if dist < 0.08:
			p.moving = false
			p.path = []
			if p.target == null and goal.face != "":
				p.facing = goal.face
		else:
			if p.goal_key != key or p.path.is_empty():
				p.goal_key = key
				p.path = path_p.find(world.solid_p, p.x, p.y, goal.x, goal.y)
				if p.path.is_empty():
					p.path = [Vector2(goal.x, goal.y)]
				p.path_i = 0
			_follow(p, 3.0, dt)
	if p.repair != null and not p.moving and Vector2(p.repair.center.x - p.x, p.repair.center.y - p.y).length() < 0.3:
		var s: Segment = p.repair
		p.activity = "Repairing the %s" % s.name.to_lower()
		p.hammer_t -= dt
		if p.hammer_t <= 0.0:
			p.hammer_t = 0.45
			events.append({"type": "hammer", "x": p.x, "y": p.y})
			var hx := s.center.x + (-0.8 if s.side == "W" else (0.8 if s.side == "E" else 0.0))
			var hy := s.center.y - (0.8 if s.side == "N" else 0.0)
			fx.hit_material(hx, hy, "metal")
		var done: float = supplies.repair_budget(dt * 9.0 * perf(p))
		if done > 0.0:
			_repair_segment(s, done)
		if s.hp >= s.max_hp:
			p.repair = null
	_combat(p, dt)


## Walk along a.path; returns true once the path is used up.
func _follow(a, speed: float, dt: float) -> bool:
	if a.path.is_empty() or a.path_i >= a.path.size():
		a.moving = false
		return true
	var target: Vector2 = a.path[a.path_i]
	var dx: float = target.x - a.x
	var dy: float = target.y - a.y
	var dist := sqrt(dx * dx + dy * dy)
	var step := speed * dt
	if dist <= step:
		a.x = target.x
		a.y = target.y
		a.path_i += 1
		if a.path_i >= a.path.size():
			a.moving = false
			return true
	else:
		a.x += dx / dist * step
		a.y += dy / dist * step
	a.moving = true
	a.walk_phase += dt * speed * 3.4
	a.facing = facing_of(dx, dy, a.facing)
	return false


## What one shot costs this person's gun from the stock.
func shot_cost(p: Person) -> float:
	return SHELL_COST if p.weapon == "shotgun" else SHOT_COST


## The weapon someone fights with right now: their own, or the butt of it when the
## stock is too low for another shot (a pike never runs dry).
func gun_of(p: Person) -> Dictionary:
	if p.gun.get("melee", false) or stock.ammo >= shot_cost(p):
		return p.gun
	return BUTT


func _find_target(p: Person):
	var rng: float = float(gun_of(p).range)
	var best = null
	var best_score := INF
	for z in zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dist := Vector2(z.x - p.x, z.y - p.y).length()
		if dist > rng:
			continue
		var inside: bool = z.x > 20 and z.x < 64 and z.y > 18 and z.y < 44
		var score := dist - (3.0 if z.state == "attack" else 0.0) - (12.0 if inside else 0.0)
		if score < best_score:
			best_score = score
			best = z
	return best


func _combat(p: Person, dt: float) -> void:
	if p.reloading > 0.0:
		p.reloading -= dt
		if p.reloading <= 0.0:
			p.mag = int(p.gun.mag)
			p.reloading = 0.0
		p.aim += ang_diff(p.aim, _rest_angle(p)) * minf(1.0, dt * 6.0)
		return
	p.cooldown -= dt
	if p.moving or (phase == "day" and not p.drafted):
		p.target = null
		p.aim += ang_diff(p.aim, _rest_angle(p)) * minf(1.0, dt * 6.0)
		return
	var gun := gun_of(p)
	if gun == BUTT and (phase == "night" or phase == "dusk" or p.drafted):
		alert("ammo-out", "danger", "Out of ammo", "The guns are silent. Send a party for more.", null, 20.0)
	var tz = p.target
	if tz == null or tz.state == "dying" or tz.state == "dead" or Vector2(tz.x - p.x, tz.y - p.y).length() > float(gun.range):
		p.target = _find_target(p)
	if p.target == null:
		p.aim += ang_diff(p.aim, _rest_angle(p)) * minf(1.0, dt * 4.0)
		return
	var z: Zombie = p.target
	var ang := atan2(z.y - 0.3 - (p.y - 0.15), z.x - p.x)
	p.aim += ang_diff(p.aim, ang) * minf(1.0, dt * 9.0)
	p.facing = facing_of(cos(ang), sin(ang), p.facing)
	if p.cooldown <= 0.0 and absf(ang_diff(p.aim, ang)) < 0.1:
		_fire(p, z, ang)


func _rest_angle(p: Person) -> float:
	var r: float = guns[p.weapon].rest
	if p.weapon == "pike":
		return r
	if p.facing == "W":
		return PI - r
	if p.facing == "N":
		return -PI / 2.0 + 0.35
	return r


func muzzle(p: Person, ang: float) -> Vector2:
	var view := "E" if p.facing == "W" else p.facing
	var pv: Vector2 = PIVOT[view]
	var mx := -pv.x if p.facing == "W" else pv.x
	var length: float = guns[p.weapon].muzzle
	return Vector2(p.x + mx + cos(ang) * length, p.y + pv.y + sin(ang) * length)


func _fire(p: Person, z: Zombie, ang: float) -> void:
	var gun := gun_of(p)
	var dist := Vector2(z.x - p.x, z.y - p.y).length()
	if gun.get("melee", false):
		p.thrust = 1.0
		p.cooldown = float(gun.cooldown) * (0.9 + rng.randf() * 0.2)
		events.append({"type": "stab", "x": p.x, "y": p.y})
		if rng.randf() < float(gun.acc):
			_hurt_zombie(z, float(gun.dmg), ang)
		return
	p.mag -= 1
	p.recoil = 1.0
	p.cooldown = float(gun.cooldown) * (0.85 + rng.randf() * 0.3)
	var m := muzzle(p, ang)
	fx.muzzle(m.x, m.y, ang, p.weapon == "shotgun" or p.weapon == "hunting")
	fx.casing(p.x, p.y - 0.15, ang, p.weapon == "shotgun")
	events.append({"type": "shot", "weapon": gun.sound, "x": p.x, "y": p.y})
	stock.ammo = maxf(0.0, stock.ammo - shot_cost(p))
	var pellets := int(gun.get("pellets", 1))
	var skill: float = float(p.def.skills.Shooting) / 10.0 * perf(p)
	var dealt := 0.0
	for k in pellets:
		var pa := ang + (rng.randf() - 0.5) * float(gun.get("spread", 0.05))
		var p_hit := float(gun.acc) * (0.75 + skill * 0.35) * (1.0 - 0.5 * pow(dist / float(gun.range), 2.0))
		var hit := rng.randf() < (p_hit * 0.7 if pellets > 1 else p_hit)
		var e: Vector2
		if hit:
			e = Vector2(z.x + (rng.randf() - 0.5) * 0.2, z.y - 0.3 + (rng.randf() - 0.5) * 0.3)
			dealt += float(gun.dmg)
		else:
			var over := dist + 1.0 + rng.randf() * 3.0
			var a2 := pa + (rng.randf() - 0.5) * 0.12
			e = Vector2(p.x + cos(a2) * over, p.y - 0.15 + sin(a2) * over)
			fx.smoke(e.x, e.y, 0.12, false)
		fx.tracer(m.x, m.y, e.x, e.y)
	if dealt > 0.0:
		_hurt_zombie(z, dealt, ang)
	if p.mag <= 0:
		p.reloading = float(gun.reload)
		p.target = null
		events.append({"type": "reload", "x": p.x, "y": p.y})
	# gunfire draws the dead
	for w in zombies:
		if w.state == "wander" and Vector2(w.x - p.x, w.y - p.y).length() < 30.0:
			w.state = "approach"


func _hurt_zombie(z: Zombie, dmg: float, ang: float) -> void:
	z.hp -= dmg
	z.stagger = 0.25
	fx.blood(z.x, z.y - 0.25, cos(ang), sin(ang), 9)
	if z.hp <= 0.0 and z.state != "dying" and z.state != "dead":
		z.state = "dying"
		z.fall = 0.0
		z.fall_dir = 1.0 if cos(ang) >= 0.0 else -1.0
		if z.slot != null:
			z.slot.who = null
			z.slot = null
		kills += 1
		fx.decal(z.x + z.fall_dir * 0.35, z.y + 0.2, 0.25, 0.9)
		events.append({"type": "thud", "x": z.x, "y": z.y})


# ----------------------------------------------------------------- zombies --

func _assign_slot(z: Zombie) -> bool:
	var best: Slot = null
	var best_score := INF
	var yard_down := yard_open()
	for s in segments:
		if s.state == 3:
			continue
		if s.kind == DOOR_KIND and not yard_down:
			continue
		var crowd := 0
		for sl in s.slots:
			if sl.who != null:
				crowd += 1
		for sl in s.slots:
			if sl.who != null:
				continue
			var score := Vector2(sl.ax - z.x, sl.ay - z.y).length() + crowd * 1.2 + rng.randf() * 4.0
			if score < best_score:
				best_score = score
				best = sl
	if best == null:
		return false
	var path: Array = path_z.find(world.solid_z, z.x, z.y, best.ax, best.ay)
	if path.is_empty():
		return false
	best.who = z
	z.slot = best
	z.path = path
	z.path_i = 0
	return true


## Whether a wall section of the yard (not a school door) is down.
func yard_open() -> bool:
	for s in segments:
		if s.kind != DOOR_KIND and s.state == 3:
			return true
	return false


## A free place at a school door that is still up, for one of the dead who cannot
## get at a person hiding in the school: the nearest, if there is a way to it.
func _assign_door_slot(z: Zombie) -> bool:
	var best: Slot = null
	var best_score := INF
	for s in segments:
		if s.kind != DOOR_KIND or s.state == 3:
			continue
		for sl in s.slots:
			if sl.who != null:
				continue
			var score := Vector2(sl.ax - z.x, sl.ay - z.y).length() + rng.randf() * 2.0
			if score < best_score:
				best_score = score
				best = sl
	if best == null:
		return false
	var path: Array = path_z.find(world.solid_z, z.x, z.y, best.ax, best.ay)
	if path.is_empty():
		return false
	best.who = z
	z.slot = best
	z.path = path
	z.path_i = 0
	return true


## Whether a point is inside the school building (not the street around it).
func inside_school(x: float, y: float) -> bool:
	return y >= float(SCHOOL_TOP_ROW) + 0.5 and y < float(H) - 5.0 and x > 20.0 and x < 64.0


## How many of the dead are inside the compound, the yard or the school (not
## counting those on their way out): the stores are theirs to ruin.
func dead_inside() -> int:
	var n := 0
	for z in zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "retreat":
			continue
		if (z.x > 20.0 and z.x < 64.0 and z.y > 18.0 and z.y < 44.0) or inside_school(z.x, z.y):
			n += 1
	return n


## Whether this person is inside the school building.
func in_school(p: Person) -> bool:
	return inside_school(p.x, p.y)


## The school's inside is open to the dead while a door is down or one of them is
## already in there (so nobody is walled in with the dead). Cheap: called every step.
func refresh_school() -> void:
	var want := false
	for s in segments:
		if s.kind == DOOR_KIND and s.state == 3:
			want = true
			break
	if not want and school_open:
		for z in zombies:
			if z.state != "dying" and z.state != "dead" and inside_school(z.x, z.y):
				want = true
				break
	if want == school_open:
		return
	school_open = want
	for i in _school_inner:
		world.solid_z[int(i)] = 0 if want else 1
		path_z.set_solid(int(i), not want)
	if want:
		events.append({"type": "banner", "text": "The school is open", "sub": "The dead are inside"})


## The ground a wall section stands on, open or shut. A school door opens to the
## dead only: people walk through it whole.
func open_segment(s: Segment, open: bool) -> void:
	if s.kind == DOOR_KIND:
		for i in s.tiles:
			world.solid_z[int(i)] = 0 if open else 1
			path_z.set_solid(int(i), not open)
		return
	world.set_walkable(s.tiles, open)
	for i in s.tiles:
		path_z.set_solid(int(i), not open)
		path_p.set_solid(int(i), not open)


## At dawn the dead go back to the city, a few a step (each is a path search).
func _dawn_sweep() -> void:
	var left := DAWN_LEAVES_PER_STEP
	for z in zombies:
		if left <= 0:
			return
		if z.state != "dying" and z.state != "dead" and z.state != "retreat":
			retreat(z)
			left -= 1


func retreat(z: Zombie) -> void:
	if z.slot != null:
		z.slot.who = null
		z.slot = null
	var best: Vector2 = spawns[0]
	var bd := INF
	for s in spawns:
		var dist := Vector2(s.x - z.x, s.y - z.y).length()
		if dist < bd:
			bd = dist
			best = s
	z.state = "retreat"
	z.path = path_z.find(world.solid_z, z.x, z.y, best.x, best.y)
	z.path_i = 0


func _breached() -> bool:
	for s in segments:
		if s.state == 3:
			return true
	return false


func _update_zombie(z: Zombie, dt: float) -> void:
	z.t += dt
	z.moving = false
	if z.state == "dying":
		z.fall = minf(1.0, z.fall + dt / 0.45)
		if z.fall >= 1.0:
			z.state = "dead"
			z.dead_t = 0.0
		return
	if z.state == "dead":
		z.dead_t += dt
		if z.dead_t > 70.0:
			z.remove = true
		return
	z.groan_t -= dt
	if z.groan_t <= 0.0:
		z.groan_t = 5.0 + rng.randf() * 12.0
		events.append({"type": "groan", "x": z.x, "y": z.y})
	if z.stagger > 0.0:
		z.stagger -= dt
		return
	var slow := z.speed * (0.85 if z.limp else 1.0)
	match z.state:
		"wander":
			z.wander_t -= dt
			if z.wander_t <= 0.0 or z.path.is_empty() or z.path_i >= z.path.size():
				z.wander_t = 6.0 + rng.randf() * 8.0
				for k in 6:
					var tx := z.x + (rng.randf() - 0.5) * 10.0
					var ty := z.y + (rng.randf() - 0.5) * 10.0
					if tx > 0 and ty > 0 and tx < W and ty < H and not world.is_solid(world.solid_z, tx, ty):
						z.path = path_z.find(world.solid_z, z.x, z.y, tx, ty)
						z.path_i = 0
						break
			_follow(z, slow * 0.55, dt)
			if bell_rung and rng.randf() < dt * 0.1:
				z.state = "approach"
		"retreat":
			if _follow(z, slow, dt):
				z.remove = true
		"approach":
			if _breached() and rng.randf() < dt and not (z.slot != null and z.slot.seg.kind == DOOR_KIND):
				if z.slot != null:
					z.slot.who = null
					z.slot = null
				z.state = "breach"
				return
			if z.slot == null and not _assign_slot(z):
				z.state = "wander"
				return
			if not z.path.is_empty() and z.path_i < z.path.size():
				_follow(z, slow, dt)
				return
			# final shuffle up against the wall
			var dx: float = z.slot.x - z.x
			var dy: float = z.slot.y - z.y
			var dist := sqrt(dx * dx + dy * dy)
			if dist < 0.05:
				z.state = "attack"
				z.facing = z.slot.face
				return
			var step := minf(dist, slow * dt)
			z.x += dx / dist * step
			z.y += dy / dist * step
			z.moving = true
			z.walk_phase += dt * slow * 3.4
			z.facing = facing_of(dx, dy, z.facing)
		"attack":
			var s: Segment = z.slot.seg
			z.facing = z.slot.face
			if s.state == 3:
				z.slot.who = null
				z.slot = null
				z.state = "breach"
				return
			z.attack_t -= dt
			if z.attack_t <= 0.0:
				z.attack_t = 1.1 + rng.randf() * 0.6
				_claw(z, s)
		"breach":
			z.repath -= dt
			var prey: Person = null
			var pd := INF
			for p in people:
				if p.downed or p.dead or p.away != null:
					continue
				var dist := Vector2(p.x - z.x, p.y - z.y).length()
				if dist < pd:
					pd = dist
					prey = p
			if prey == null:
				return
			if pd < 0.7:
				z.facing = facing_of(prey.x - z.x, prey.y - z.y, z.facing)
				z.attack_t -= dt
				if z.attack_t <= 0.0:
					z.attack_t = 1.3
					_bite(z, prey)
				return
			if z.repath <= 0.0 or z.path.is_empty():
				z.repath = 1.0
				if world.is_solid(world.solid_z, z.x, z.y):
					# a survivor who turned inside the school stands where the dead
					# cannot walk: there they hunt by the people's paths
					z.path = path_p.find(world.solid_p, z.x, z.y, prey.x, prey.y)
				else:
					z.path = path_z.find(world.solid_z, z.x, z.y, prey.x, prey.y)
				z.path_i = 0
				if z.path.is_empty() and not school_open and in_school(prey) and _assign_door_slot(z):
					z.state = "approach"
					return
			_follow(z, slow * 1.1, dt)


func _claw(z: Zombie, s: Segment) -> void:
	_damage_segment(s, 1.0 + rng.randf() * 1.3)
	var mat := "wood" if (s.kind == "pallets" or s.kind == DOOR_KIND) else ("stone" if s.kind == "blocks" else "metal")
	var from_north := s.side == "N" or s.side == "S"
	var nx := 0.0 if from_north else (1.0 if s.side == "W" else -1.0)
	var ny := 1.0 if from_north else 0.0
	if rng.randf() < 0.6:
		fx.hit_material(z.x + nx * 0.35, z.y + ny * 0.25, mat)
	events.append({"type": "claw", "material": mat, "x": z.x, "y": z.y})
	var pct := roundi(s.hp / s.max_hp * 100.0)
	alert("seg-%d" % s.id, "danger" if pct < 34 else "warn", "%s under attack" % s.name, "%d%% intact" % pct, s.center, 4.0)
	medical.on_wall_claw(z, s)


func _damage_segment(s: Segment, amount: float) -> void:
	s.hp = maxf(0.0, s.hp - amount)
	_segment_state(s)


func _repair_segment(s: Segment, amount: float) -> void:
	s.hp = minf(s.max_hp, s.hp + amount)
	_segment_state(s)


func _segment_state(s: Segment) -> void:
	var f := s.hp / s.max_hp
	var st := 3 if s.hp <= 0.0 else (2 if f < 0.33 else (1 if f < 0.66 else 0))
	if s.state == 3 and st != 3 and f < 0.4:
		st = 3 # rebuilding a breach takes a while
	if st == s.state:
		return
	var was := s.state
	s.state = st
	if st == 3:
		open_segment(s, true)
		events.append({"type": "crash", "x": s.center.x, "y": s.center.y})
		events.append({"type": "banner", "text": "Breach!", "sub": "The %s is down" % s.name.to_lower()})
		alert("breach-%d" % s.id, "danger", "Breach at the %s" % s.name.to_lower(), "Walkers are getting in", s.center, 30.0)
	elif was == 3:
		open_segment(s, false)
	if on_segment_change.is_valid():
		on_segment_change.call(s)


func _bite(z: Zombie, p: Person) -> void:
	p.hp = maxf(0.0, p.hp - (9.0 + rng.randf() * 6.0))
	fx.blood(p.x, p.y - 0.25, p.x - z.x, p.y - z.y, 8)
	events.append({"type": "bite", "x": p.x, "y": p.y})
	alert("hurt-%s" % p.id, "danger", "%s is being bitten" % p.first, "%d%% health" % roundi(p.hp), Vector2(p.x, p.y), 6.0)
	medical.after_bite(z, p)
	if p.hp <= 0.0 and not p.downed:
		medical.on_downed(p, "bite")


func _separate() -> void:
	var n := zombies.size()
	for i in n:
		var a: Zombie = zombies[i]
		if a.state == "dead" or a.state == "dying":
			continue
		for j in range(i + 1, n):
			var b: Zombie = zombies[j]
			if b.state == "dead" or b.state == "dying":
				continue
			var dx := b.x - a.x
			var dy := b.y - a.y
			var d2 := dx * dx + dy * dy
			if d2 > 0.3 or d2 < 1e-6:
				continue
			var dist := sqrt(d2)
			var push := (0.55 - dist) * 0.5
			var ux := dx / dist
			var uy := dy / dist
			var ma := a.state != "attack"
			var mb := b.state != "attack"
			if ma:
				_nudge(a, -ux * push * (1.0 if mb else 2.0), -uy * push * (1.0 if mb else 2.0))
			if mb:
				_nudge(b, ux * push * (1.0 if ma else 2.0), uy * push * (1.0 if ma else 2.0))


## Push apart in the open only: a walker already shuffling into the wall line
## is left alone, and nobody is pushed into a wall.
func _nudge(z: Zombie, dx: float, dy: float) -> void:
	if world.is_solid(world.solid_z, z.x, z.y):
		return
	var nx := z.x + dx
	var ny := z.y + dy
	if nx <= 0.0 or ny <= 0.0 or nx >= W or ny >= H:
		return
	if world.is_solid(world.solid_z, nx, ny):
		return
	z.x = nx
	z.y = ny
