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
	{"id": "kit", "name": "Kit", "role": "Kid", "key": "ana", "scale": 0.62, "look": {"top": "#c9553a", "outer": "#c9553a", "pants": "#4a5a7a", "skin": "#c69877"}, "route": [
		{"at": Vector2(30.0, 26.5), "secs": 4.0, "work": "", "face": "S", "say": "playing"},
		{"at": Vector2(44.0, 44.0), "secs": 4.0, "work": "", "face": "E", "say": "playing"},
		{"at": Vector2(26.0, 46.0), "secs": 5.0, "work": "rest", "face": "S", "say": "playing"},
	]},
	{"id": "pip", "name": "Pip", "role": "Kid", "key": "dez", "scale": 0.58, "look": {"top": "#3a7aa0", "pants": "#6a5a3a", "skin": "#8a5a3c", "hatColor": "#c9a43a"}, "route": [
		{"at": Vector2(27.0, 46.5), "secs": 5.0, "work": "rest", "face": "N", "say": "playing"},
		{"at": Vector2(32.0, 27.0), "secs": 3.0, "work": "", "face": "S", "say": "playing"},
		{"at": Vector2(45.0, 43.0), "secs": 4.0, "work": "", "face": "W", "say": "playing"},
	]},
]

var sim
var world
var base
var data: Dictionary
var members: Array = []    # {p: Person, def: Dictionary, i: stop index, state: "walk"|"work"|"wait", path, pi, t, secs, node}
var floaters: Array = []    # {text, pos, t, col}
var tally := {}
var tod := 8.0    # hour of the day, set by the game
var _meal_id := -1    # what each stock got from the crew since the start


func setup(s, w, b, d: Dictionary) -> void:
	sim = s
	world = w
	base = b
	data = d
	var defs: Dictionary = {}
	for pd in d.people:
		defs[String(pd.id)] = pd
	var n := 0
	for r in ROSTER:
		var src: Dictionary = (defs[String(r.key)] as Dictionary).duplicate(true)
		src["id"] = String(r.id)
		src["name"] = String(r.name)
		var look: Dictionary = (src.look as Dictionary).duplicate(true)
		for k in r.look:
			look[k] = r.look[k]
		src["look"] = look
		src["station"] = ""
		src["post_id"] = ""
		var p = sim.make_person(src)
		p.player = false
		var m := {"p": p, "def": r, "i": 0, "state": "wait", "path": [], "pi": 0, "t": 0.0, "secs": 0.0, "key": String(r.key), "say": String(r.role)}
		var at := _stand(r)
		if r.has("stand"):
			at = _tower_spot(String(r.stand))
			p.work = String(r.work)
			p.facing = String(r.face)
			m.state = "post"
		else:
			var first = r.route[0]
			at = _where(first.at)
			at = at + Vector2(float(n % 3) * 0.4 - 0.4, 0.0)
		p.x = at.x
		p.y = at.y
		p.hp = 100.0
		p.moving = false
		members.append(m)
		n += 1


func _stand(r: Dictionary) -> Vector2:
	return Vector2(48.0, 48.0)


func _tower_spot(name: String) -> Vector2:
	match name:
		"tower_e":
			return Vector2(53.0, 52.0)
		"tower_nw":
			return Vector2(8.0, 6.0)
		"tower_se":
			return Vector2(86.0, 52.0)
		"tower_w":
			return Vector2(42.0, 52.0)
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
	for m in members:
		if m.state == "post":
			m.p.work_t = float(m.p.work_t) + dt
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
			# start walking to the stop (a stop that needs stock the base has not got is skipped after a short wait)
			var tgt := _where(stop.at)
			m.path = sim.path_p.find(world.solid_p, p.x, p.y, tgt.x, tgt.y)
			m.pi = 0
			m.state = "walk"
			p.work = ""
		"walk":
			if m.pi >= m.path.size():
				m.state = "arrive"
				return
			var wp: Vector2 = m.path[m.pi]
			var to := wp - Vector2(p.x, p.y)
			var dist := to.length()
			if dist < 0.12:
				m.pi += 1
				return
			var step := minf(dist, SPEED * dt)
			var dir := to / dist
			p.x += dir.x * step
			p.y += dir.y * step
			p.facing = sim.facing_of(dir.x, dir.y, p.facing)
			p.moving = true
			p.walk_phase += dt * 6.0
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
					m.erase("eat")
				else:
					_finish(m, stop, stores)
					m.i = (int(m.i) + 1) % r.route.size()
				m.state = "wait"
				p.work = ""
				p.work_t = 0.0


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
		var v := float(give[k])
		stores[k] = maxf(0.0, float(stores.get(k, 0.0)) + v)
		tally[k] = float(tally.get(k, 0.0)) + v
		parts.append("%s%s %s" % ["+" if v > 0 else "", ("%d" % int(v)) if absf(v - round(v)) < 0.01 else ("%.1f" % v), k])
	if not parts.is_empty():
		floaters.append({"text": ", ".join(parts), "pos": Vector2(m.p.x, m.p.y - 1.9), "t": 0.0, "col": Color(0.7, 1.0, 0.6) if float(give.values()[0]) > 0 else Color(1.0, 0.75, 0.5)})
