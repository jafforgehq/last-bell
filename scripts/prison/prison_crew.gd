## EXPERIMENT (prison extraction): the ten people of the compound and their work loops. A person is a real `Sim.Person` made by `sim.make_person` (so the real PawnNode draws them, with the
## real work poses of work_anim.gd) but is NOT in `sim.people`: the colony's jobs and tactics never see them. Each one walks a route of stops with the town's path finder, works at a stop for a
## few seconds (`Person.work` word, `work_t`) and then its effect changes the base's stores (food, water, scrap, ammo, meds) and a little "+2 food" floats up.
extends RefCounted

const SPEED := 1.7
const IDLE_RETRY := 2.5

## key: the body of the pawn art (dez, ana, marcus, walt, hector); look: palette overrides so that two on one body read as two people.
const ROSTER := [
	{"id": "walt", "name": "Walt", "role": "Gate guard", "key": "walt", "look": {}, "stand": "tower_e", "work": "watch", "face": "S"},
	{"id": "dez", "name": "Dez", "role": "Tower guard", "key": "dez", "look": {}, "stand": "tower_nw", "work": "watch", "face": "S"},
	{"id": "rae", "name": "Rae", "role": "Tower guard", "key": "ana", "look": {"top": "#3a4a3a", "outer": "#555a50", "pants": "#2c2c34", "skin": "#a6734e"}, "stand": "tower_se", "work": "watch", "face": "S"},
	{"id": "sol", "name": "Sol", "role": "Gate guard", "key": "hector", "look": {"top": "#4a4a50", "pants": "#2c3038", "skin": "#c69877"}, "stand": "tower_w", "work": "watch", "face": "S"},
	{"id": "mia", "name": "Mia", "role": "Cook", "key": "ana", "look": {"top": "#d9d4c4", "outer": "#a8483c", "pants": "#3d3d44", "skin": "#8a5a3c"}, "route": [
		{"at": "fridge", "secs": 3.0, "work": "sort", "face": "N"},
		{"at": "stove", "secs": 8.0, "work": "bench", "face": "N", "say": "cooking"},
		{"at": "serve", "secs": 5.0, "work": "sort", "face": "S", "give": {"food": -4.0, "water": -3.0}, "say": "serving"},
		{"at": "chat_a1", "secs": 9.0, "work": "", "face": "E", "say": "chatting with Owen", "chat": true},
	]},
	{"id": "marcus", "name": "Marcus", "role": "Gardener", "key": "marcus", "look": {}, "route": [
		{"at": "garden1", "secs": 9.0, "work": "garden", "face": "S", "give": {"food": 1.5}, "say": "hoeing"},
		{"at": "garden2", "secs": 9.0, "work": "garden", "face": "S", "give": {"food": 1.5}, "say": "hoeing"},
		{"at": "chat_b1", "secs": 10.0, "work": "", "face": "E", "say": "chatting with Nia", "chat": true},
	]},
	{"id": "nia", "name": "Nia", "role": "Gardener", "key": "ana", "look": {"top": "#7a8a4a", "outer": "#c9b25a", "pants": "#5a4a3a", "skin": "#5e3b2a"}, "route": [
		{"at": "garden3", "secs": 9.0, "work": "garden", "face": "S", "give": {"food": 1.5}, "say": "planting"},
		{"at": "garden1", "secs": 9.0, "work": "garden", "face": "S", "give": {"food": 1.5}, "say": "planting"},
		{"at": "chat_b2", "secs": 10.0, "work": "", "face": "W", "say": "chatting with Marcus", "chat": true},
	]},
	{"id": "ana", "name": "Ana", "role": "Medic", "key": "ana", "look": {}, "route": [
		{"at": "bed", "secs": 10.0, "work": "nurse", "face": "E", "say": "tending a patient"},
		{"at": "meds", "secs": 9.0, "work": "sort", "face": "S", "need": {"scrap": 1.0}, "give": {"scrap": -1.0, "meds": 0.5}, "say": "mixing meds"},
	]},
	{"id": "hector", "name": "Hector", "role": "Mechanic", "key": "hector", "look": {}, "route": [
		{"at": "bench1", "secs": 14.0, "work": "bench", "face": "N", "need": {"scrap": 1.0}, "give": {"scrap": -1.0, "ammo": 2.0}, "say": "loading rounds"},
		{"at": "bench2", "secs": 8.0, "work": "hammer", "face": "N", "say": "at the vise"},
	]},
	{"id": "tomas", "name": "Tomas", "role": "Fence crew", "key": "dez", "look": {"top": "#6a5a44", "pants": "#3a4a5a", "hatColor": "#8a5a2a", "skin": "#9a6a48"}, "route": [
		{"at": "fence_w", "secs": 9.0, "work": "mend", "face": "S", "give": {"scrap": -0.5}, "say": "mending the fence"},
		{"at": "fence_m", "secs": 9.0, "work": "mend", "face": "S", "say": "mending the fence"},
		{"at": "fence_e", "secs": 9.0, "work": "mend", "face": "S", "say": "mending the fence"},
	]},
	{"id": "owen", "name": "Owen", "role": "Hauler", "key": "marcus", "look": {"top": "#4a5a7a", "pants": "#4a4036", "skin": "#c69877", "backpack": "#8a5a2a"}, "route": [
		{"at": "well", "secs": 6.0, "work": "haul", "face": "S", "give": {"water": 4.0}, "say": "drawing water"},
		{"at": "stores_in", "secs": 5.0, "work": "haul", "face": "N", "say": "stacking crates"},
		{"at": "chat_a2", "secs": 9.0, "work": "", "face": "W", "say": "chatting with Mia", "chat": true},
	]},
	{"id": "june", "name": "June", "role": "Patrol", "key": "hector", "look": {"top": "#3c4a3a", "pants": "#2c2c34", "skin": "#e0b393"}, "route": [
		{"at": Vector2(9.5, 27.0), "secs": 2.0, "work": "radio", "face": "S", "say": "on patrol"},
		{"at": Vector2(9.5, 48.0), "secs": 1.0, "work": "", "face": "E"},
		{"at": Vector2(36.0, 49.0), "secs": 1.0, "work": "", "face": "S"},
		{"at": Vector2(60.0, 49.0), "secs": 2.0, "work": "radio", "face": "S", "say": "on patrol"},
		{"at": Vector2(51.5, 50.3), "secs": 14.0, "work": "watch", "face": "S", "say": "relieving the gate guard"},
		{"at": Vector2(61.0, 26.0), "secs": 1.0, "work": "", "face": "N"},
		{"at": Vector2(36.0, 26.0), "secs": 1.0, "work": "", "face": "W"},
	]},
	{"id": "kit", "name": "Kit", "role": "Kid", "key": "ana", "scale": 0.62, "unarmed": true, "play": true, "look": {"top": "#c9553a", "outer": "#c9553a", "pants": "#4a5a7a", "skin": "#c69877"}},
	{"id": "pip", "name": "Pip", "role": "Kid", "key": "dez", "scale": 0.58, "unarmed": true, "play": true, "look": {"top": "#3a7aa0", "pants": "#6a5a3a", "skin": "#8a5a3c", "hatColor": "#c9a43a"}},
]

## CLEAR PHASE: the survivors that walk in with Ruth. They follow her and shoot (prison_game.gd `_allies`); they have hit points and can go down.
const ALLIES := [
	{"id": "cole", "name": "Cole", "role": "Ally", "key": "walt", "ally": true, "look": {"top": "#5a4a3a", "pants": "#3a3a44", "skin": "#c69877"}},
	{"id": "bea", "name": "Bea", "role": "Ally", "key": "ana", "ally": true, "look": {"top": "#6a3a4a", "outer": "#3a4a5a", "pants": "#2c2c34", "skin": "#7a4e34"}},
	{"id": "ike", "name": "Ike", "role": "Ally", "key": "hector", "ally": true, "look": {"top": "#3a5a4a", "pants": "#4a4036", "skin": "#e0b393"}},
]
## MANAGED PHASE: the three allies are crew now: a name, a job and a place, no follow code, no "ally" key (so no health bar, no 'ready' tag, no revive). "ex_ally" only tells the siege to forget them when lost.
const CREW_FROM_ALLIES := [
	{"id": "cole", "name": "Cole", "role": "Gate watch", "key": "walt", "ex_ally": true, "look": {"top": "#5a4a3a", "pants": "#3a3a44", "skin": "#c69877"}, "route": [
		{"at": Vector2(44.5, 50.3), "secs": 20.0, "work": "watch", "face": "S", "say": "watching the gate"},
		{"at": Vector2(51.5, 50.3), "secs": 20.0, "work": "watch", "face": "S", "say": "watching the gate"},
	]},
	{"id": "bea", "name": "Bea", "role": "Yard patrol", "key": "ana", "ex_ally": true, "look": {"top": "#6a3a4a", "outer": "#3a4a5a", "pants": "#2c2c34", "skin": "#7a4e34"}, "route": [
		{"at": Vector2(20.0, 46.0), "secs": 6.0, "work": "watch", "face": "S", "say": "on patrol"},
		{"at": Vector2(36.0, 49.0), "secs": 2.0, "work": "", "face": "E"},
		{"at": Vector2(70.0, 47.0), "secs": 6.0, "work": "watch", "face": "S", "say": "on patrol"},
		{"at": Vector2(36.0, 41.0), "secs": 2.0, "work": "", "face": "W"},
	]},
	{"id": "ike", "name": "Ike", "role": "Quartermaster", "key": "hector", "ex_ally": true, "look": {"top": "#3a5a4a", "pants": "#4a4036", "skin": "#e0b393"}, "route": [
		{"at": "stores_out", "secs": 7.0, "work": "haul", "face": "N", "say": "carrying crates"},
		{"at": "stores_in", "secs": 7.0, "work": "sort", "face": "N", "say": "counting the stores"},
	]},
]
const ALLY_HP := 45.0
const YARD := Rect2(9.0, 43.0, 28.0, 11.0)    # where the kids play

var sim
var world
var base
var data: Dictionary
var members: Array = []    # {p: Person, def: Dictionary, i: stop index, state: "walk"|"work"|"wait", path, pi, t, secs, node}
var floaters: Array = []    # {text, pos, t, col}
var tally := {}
var tod := 8.0    # hour of the day, set by the game
var play_t := 0.0
var ball := Vector2(24.0, 49.0)    # the kids' ball
var econ_owned: Array = []    # ECON hook: stock keys the economy (prison_econ.gd) owns; a stop's `give` of these is only for show
var _meal_id := -1    # what each stock got from the crew since the start


func setup(s, w, b, d: Dictionary, clear: bool = false) -> void:
	sim = s
	world = w
	base = b
	data = d
	if clear:
		for i in ALLIES.size():
			_make(ALLIES[i], Vector2(3.5, 33.2 + float(i) * 1.1))
		return
	var n := 0
	for r in ROSTER:
		_make(r, Vector2.ZERO, n)
		n += 1


## One person of a roster entry (a real Person that is not in `sim.people`), placed at `at` (the roster's own place when it is ZERO). Returns the member.
func _make(r: Dictionary, at_in: Vector2, n: int = 0) -> Dictionary:
	var defs: Dictionary = {}
	for pd in data.people:
		defs[String(pd.id)] = pd
	var src: Dictionary = (defs[String(r.key)] as Dictionary).duplicate(true)
	src["id"] = String(r.id)
	src["name"] = String(r.name)
	src["unarmed"] = bool(r.get("unarmed", false))
	var look: Dictionary = (src.look as Dictionary).duplicate(true)
	for k in r.look:
		look[k] = r.look[k]
	src["look"] = look
	src["station"] = ""
	src["post_id"] = ""
	var p = sim.make_person(src)
	p.player = false
	var m := {"p": p, "def": r, "i": 0, "state": "wait", "path": [], "pi": 0, "t": 0.0, "secs": 0.0, "key": String(r.key), "say": String(r.role)}
	var at := at_in
	if r.has("ally"):
		m.state = "ally"
		m["hp"] = ALLY_HP
		m["cd"] = 1.0
		m["bite"] = 0.0
		m["down_t"] = 0.0
		m["repath"] = 0.0
	elif r.has("play"):
		m.state = "play"
		m["role"] = "flee" if String(r.id) == "kit" else "chase"
		m["repath"] = 0.0
		m["tgt"] = Vector2.ZERO
		m["swap_cd"] = 0.0
		if at == Vector2.ZERO:
			at = Vector2(20.0 + float(n % 2) * 2.0, 50.0)
	elif r.has("stand"):
		if at == Vector2.ZERO:
			at = _tower_spot(String(r.stand))
		p.work = String(r.work)
		p.facing = String(r.face)
		m.state = "post"
	elif at == Vector2.ZERO:
		at = _where(r.route[0].at) + Vector2(float(n % 3) * 0.4 - 0.4, 0.0)
	p.x = at.x
	p.y = at.y
	p.hp = 100.0
	p.moving = false
	members.append(m)
	return m


## CLEAR PHASE: a zone is cleared and this person is free: they appear at `at` and go to their job (a guard walks to the foot of the tower and climbs). Returns the member.
func release(id: String, at: Vector2) -> Dictionary:
	for r in ROSTER:
		if String(r.id) != id:
			continue
		var m := _make(r, at, members.size())
		if r.has("stand"):
			var spot := _tower_spot(String(r.stand))
			m.state = "walk"
			m["to_post"] = spot
			m.path = sim.path_p.find(world.solid_p, at.x, at.y, spot.x, spot.y + 2.0)
			m.pi = 0
			m.p.work = ""
		return m
	return {}


func _stand(r: Dictionary) -> Vector2:
	return Vector2(48.0, 48.0)


func _tower_spot(name: String) -> Vector2:
	match name:
		"tower_e":
			return Vector2(53.5, 52.5)
		"tower_nw":
			return Vector2(8.5, 6.5)
		"tower_se":
			return Vector2(86.5, 52.5)
		"tower_w":
			return Vector2(42.5, 52.5)
	return Vector2(48.0, 48.0)


func _where(at) -> Vector2:
	if at is Vector2:
		return at
	return base.stations.get(String(at), Vector2(48.0, 40.0))


func _meal_window() -> int:
	for k in [[7.0, 8.5], [13.0, 14.5], [19.0, 20.5]]:
		if tod >= k[0] and tod < k[1]:
			return int(k[0])
	return -1


func update(dt: float, stores: Dictionary) -> void:
	_meal_id = _meal_window()
	play_t += dt
	for m in members:
		if m.state == "post":
			m.p.work_t = float(m.p.work_t) + dt
			continue
		if m.state == "ally" or m.state == "downed":
			continue    # the game moves allies (follow, shoot, bites)
		if m.state == "down":
			continue    # bitten in a siege (prison_siege.gd): lying there until it is over
		if m.state == "play":
			_play(m, dt)
			continue
		if m.has("to_post"):
			_to_post(m, dt)
			continue
		_step_member(m, dt, stores)
	for f in floaters:
		f.t = float(f.t) + dt
	floaters = floaters.filter(func(f): return float(f.t) < 2.2)


func _step_member(m: Dictionary, dt: float, stores: Dictionary) -> void:
	var p = m.p
	var r: Dictionary = m.def
	var stop: Dictionary = r.route[m.i]
	if m.has("eat"):
		stop = m.eat
	match m.state:
		"wait":
			if _meal_id >= 0 and int(m.get("ate", -1)) != _meal_id and not m.has("eat"):
				var seat: Vector2 = base.stations.canteen + Vector2(float(int(m.p.x * 7.0) % 9) * 1.1 - 4.0, float((int(m.p.y) % 3) * 3 - 3))
				m["eat"] = {"at": seat, "secs": 12.0, "work": "", "face": "S", "say": "eating", "meal": true}
				m["ate"] = _meal_id
				stop = m.eat
			if not m.has("eat") and not (m.get("clean_q", []) as Array).is_empty():    # a clean-up stop (prison_clean.gd), taken after the meals
				m["eat"] = (m.clean_q as Array).pop_front()
				stop = m.eat
			# start walking to the stop (a stop that needs stock the base has not got is skipped after a short wait)
			var tgt := _where(stop.at)
			m.path = sim.path_p.find(world.solid_p, p.x, p.y, tgt.x, tgt.y)
			m.pi = 0
			m.state = "walk"
			p.work = ""
		"walk":
			if _advance(m, dt, SPEED):
				m.state = "arrive"
		"arrive":
			p.moving = false
			if stop.get("meal", false):
				pass
			if stop.has("need") and not _have(stores, stop.need):
				m.state = "idle"
				m.t = 0.0
				m.say = "waiting for scrap"
				p.work = ""
				return
			m.state = "work"
			m.t = 0.0
			p.work = String(stop.get("work", ""))
			p.work_t = 0.0
			p.facing = String(stop.get("face", p.facing))
			m.say = String(stop.get("say", r.role))
		"idle":
			m.t = float(m.t) + dt
			if m.t >= IDLE_RETRY:
				m.state = "arrive"
		"work":
			m.t = float(m.t) + dt
			p.work_t = float(m.t)
			if float(m.t) >= float(stop.secs):
				if m.has("eat"):
					if bool(m.eat.get("clean", false)):
						floaters.append({"text": "+clean", "pos": Vector2(m.p.x, m.p.y - 1.9), "t": 0.0, "col": Color(0.6, 0.9, 1.0)})
					m.erase("eat")
				else:
					_finish(m, stop, stores)
					m.i = (int(m.i) + 1) % r.route.size()
				m.state = "wait"
				p.work = ""
				p.work_t = 0.0


## One step along m.path at `speed`; true when the path is done.
func _advance(m: Dictionary, dt: float, speed: float) -> bool:
	var p = m.p
	if m.pi >= m.path.size():
		p.moving = false
		return true
	var wp: Vector2 = m.path[m.pi]
	var to := wp - Vector2(p.x, p.y)
	var dist := to.length()
	if dist < 0.12:
		m.pi += 1
		return false
	var step := minf(dist, speed * dt)
	var dir := to / dist
	p.x += dir.x * step
	p.y += dir.y * step
	p.facing = sim.facing_of(dir.x, dir.y, p.facing)
	p.moving = true
	p.walk_phase += dt * (6.0 * speed / SPEED)
	return false


## A freed guard walks to the foot of the tower, then stands on the deck.
func _to_post(m: Dictionary, dt: float) -> void:
	if _advance(m, dt, SPEED * 1.4):
		var r: Dictionary = m.def
		var spot: Vector2 = m.to_post
		m.erase("to_post")
		m.p.x = spot.x
		m.p.y = spot.y
		m.p.work = String(r.work)
		m.p.facing = String(r.face)
		m.p.moving = false
		m.state = "post"


## The kids: tag in the yard (one runs, one chases; a touch swaps them), a ball that rolls along, a hopscotch that the runner visits. Never armed, never on a route.
func _play(m: Dictionary, dt: float) -> void:
	var p = m.p
	var other = null
	for q in members:
		if q.state == "play" and q != m:
			other = q
	m.repath = float(m.repath) - dt
	m.swap_cd = float(m.swap_cd) - dt
	p.work = ""
	var speed := 3.3 if m.role == "flee" else 2.9
	if other != null and m.role == "chase":
		var d := Vector2(p.x - other.p.x, p.y - other.p.y).length()
		if d < 0.9 and float(m.swap_cd) <= 0.0:
			m.role = "flee"
			other.role = "chase"
			m.swap_cd = 3.0
			other.swap_cd = 3.0
			m.say = "tag! run!"
			other.say = "gotcha, now you!"
			m.repath = 0.0
			other.repath = 0.0
	if float(m.repath) <= 0.0:
		m.repath = 0.5
		var tgt: Vector2
		if m.role == "chase" and other != null:
			tgt = Vector2(other.p.x, other.p.y)
		else:
			tgt = m.tgt
			if tgt == Vector2.ZERO or Vector2(p.x, p.y).distance_to(tgt) < 1.2:
				tgt = Vector2(randf_range(YARD.position.x, YARD.end.x), randf_range(YARD.position.y, YARD.end.y))
				if randf() < 0.3:
					tgt = HOPSCOTCH
				m.tgt = tgt
		m.path = sim.path_p.find(world.solid_p, p.x, p.y, tgt.x, tgt.y)
		m.pi = 0
	_advance(m, dt, speed)
	if m.role == "flee" and String(m.say) == "Kid":
		m.say = "running"
	# the ball rolls ahead of whoever runs
	var runner = m if m.role == "flee" else other
	if runner != null:
		var want := Vector2(runner.p.x, runner.p.y) + Vector2(0.8, 0.3)
		ball += (want - ball) * (1.0 - exp(-2.5 * dt))


const HOPSCOTCH := Vector2(14.0, 52.0)

func _have(stores: Dictionary, need: Dictionary) -> bool:
	for k in need:
		if float(stores.get(k, 0.0)) < float(need[k]):
			return false
	return true


func _finish(m: Dictionary, stop: Dictionary, stores: Dictionary) -> void:
	if stop.get("chat", false):
		floaters.append({"text": ["...", "heh", "right?", "no way"][int(m.p.x * 3.0) % 4], "pos": Vector2(m.p.x, m.p.y - 1.9), "t": 0.0, "col": Color(1, 1, 0.9)})
	var give: Dictionary = stop.get("give", {})
	var parts: Array = []
	for k in give:
		if econ_owned.has(k):
			continue
		var v := float(give[k])
		stores[k] = maxf(0.0, float(stores.get(k, 0.0)) + v)
		tally[k] = float(tally.get(k, 0.0)) + v
		parts.append("%s%s %s" % ["+" if v > 0 else "", ("%d" % int(v)) if absf(v - round(v)) < 0.01 else ("%.1f" % v), k])
	if not parts.is_empty():
		floaters.append({"text": ", ".join(parts), "pos": Vector2(m.p.x, m.p.y - 1.9), "t": 0.0, "col": Color(0.7, 1.0, 0.6) if float(give.values()[0]) > 0 else Color(1.0, 0.75, 0.5)})
