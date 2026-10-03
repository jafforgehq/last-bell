## What the tests of the community's ideas (round 20, scripts/sim/initiative.gd) share: a small avatar game at a time of day, and fakes
## of the other two modules of the round (relations and specialists), so that these tests say what the INITIATIVE module does with
## what those modules answer, whatever state their own builders' code is in. The fakes have exactly the methods the contract
## (docs/superpowers/plans/2026-10-03-round-20.md) names, and no others.
extends RefCounted

const Helpers := preload("res://tests/helpers.gd")


## The relations module as the contract describes it, with answers a test sets.
class FakeRelations:
	extends RefCounted
	var sim
	var enabled := true
	var voice_id := ""
	var community := 55.0
	var friends := {}    # person id -> [ids], strongest first
	var rivals := {}
	var affinities := {}    # "a|b" (ids sorted) -> value
	var loss := {}
	var adds: Array = []    # [{"a", "b", "delta", "why"}]

	func setup(s) -> void:
		sim = s

	func start() -> void:
		pass

	func person_added(_p) -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func active() -> bool:
		return true

	func _person(id):
		for p in sim.people:
			if String(p.id) == String(id):
				return p
		return null

	func voice():
		return _person(voice_id) if voice_id != "" else null

	func community_trust() -> float:
		return community

	func friends_of(p) -> Array:
		var out: Array = []
		for id in friends.get(String(p.id), []):
			var q = _person(id)
			if q != null and not q.dead and not q.turned:
				out.append(q)
		return out

	func rivals_of(p) -> Array:
		var out: Array = []
		for id in rivals.get(String(p.id), []):
			var q = _person(id)
			if q != null and not q.dead and not q.turned:
				out.append(q)
		return out

	func affinity(a, b) -> float:
		var x := String(a.id) if typeof(a) != TYPE_STRING else String(a)
		var y := String(b.id) if typeof(b) != TYPE_STRING else String(b)
		return float(affinities.get("%s|%s" % [x, y] if x < y else "%s|%s" % [y, x], 0.0))

	func add(a, b, delta: float, why: String) -> void:
		adds.append({"a": String(a.id), "b": String(b.id), "delta": delta, "why": why})

	func recent_loss() -> Dictionary:
		return loss.duplicate()

	# (the rest of the contract, neutral: the hooks of the other files call these whatever the test is about)
	func kind(_a, _b) -> String:
		return ""

	func word(_a, _b) -> String:
		return ""

	func partner_of(_p):
		return null

	func circle(_p) -> Array:
		return []

	func is_close(_p, _q) -> bool:
		return false

	func describe(_p) -> Dictionary:
		return {}

	func standing(_p) -> float:
		return 0.0

	func company_pull(_contact, _verb: String) -> float:
		return 0.0

	func company_reason(_contact, _what: String, _station_id := "", _with_ids := []) -> String:
		return ""

	func rival_near(_p):
		return null

	func grief_mult(_p, _lost) -> float:
		return 1.0

	func fit_adjust(_p, _station_id: String) -> float:
		return 0.0

	func succession_bonus(_p) -> float:
		return 0.0

	func on_trust_moved(_p, _delta: float) -> void:
		pass

	func on_treated(_healer, _patient, _kind: String) -> void:
		pass

	func on_trip(_came: Array, _lost: Array, _party: Dictionary) -> void:
		pass

	func on_lost(_p, _how: String) -> void:
		pass

	func on_downed(_p) -> void:
		pass

	## The sum of what was added to a pair, in either order.
	func added(a: String, b: String) -> float:
		var sum := 0.0
		for e in adds:
			if (e.a == a and e.b == b) or (e.a == b and e.b == a):
				sum += float(e.delta)
		return sum


## The specialists module as the contract describes it.
class FakeSpecialists:
	extends RefCounted
	var sim
	var enabled := true
	var holders := {}    # title id -> person id
	var trips := {}    # person id -> trips

	func setup(s) -> void:
		sim = s

	func start() -> void:
		pass

	func person_added(_p) -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func active() -> bool:
		return true

	func holder(title_id: String):
		var id := String(holders.get(title_id, ""))
		for p in sim.people:
			if String(p.id) == id and not p.dead and not p.turned:
				return p
		return null

	func title_of(p) -> Dictionary:
		for t in holders:
			if String(holders[t]) == String(p.id):
				return {"id": t, "name": "the " + String(t), "short": String(t), "since_day": 1}
		return {}

	func opinion_title(p) -> String:
		return String(title_of(p).get("name", ""))

	func record_of(p) -> Dictionary:
		return {"trips": int(trips.get(String(p.id), 0)), "since": {}}

	# (the rest of the contract, neutral)
	func gaps() -> Array:
		return []

	func mult(_p, _key: String) -> float:
		return 1.0

	func add(_p, _key: String) -> float:
		return 0.0

	func fit_bonus(_p, _station_id: String) -> float:
		return 0.0

	func party_mult(_people: Array) -> float:
		return 1.0

	func on_trip(_came: Array, _lost: Array, _party: Dictionary) -> void:
		pass


## Puts the clock at `hour` of `day` the way the radio tests do.
static func at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day
	sim.supplies.meal_day = day
	sim.supplies.meals_done = 3


## A settlement game with an avatar (Ruth) and `crew` people (3: Ruth, Dez, Marcus; 4 adds Ana, 5 Walt), at 09:00 on day 3, a quiet
## yard, plenty of scrap, food and ammo: nothing in it needs anything until a test makes it. The fakes of the two other modules
## are in (`rel`, `spec`) with nobody's friendship and no titles. `g.world` is to be freed by the caller.
static func game(crew: int = 4, seed_value: int = 1, fakes: bool = true) -> Dictionary:
	var g := Helpers.make(seed_value, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.avatar.set_player("ruth")
	sim.radio.start()
	at(sim, 3, 9.0)
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 60.0, "meds": 10.0}
	sim.events.clear()
	if fakes:
		var rel := FakeRelations.new()
		rel.setup(sim)
		sim.relations = rel
		var spec := FakeSpecialists.new()
		spec.setup(sim)
		sim.specialists = spec
		g["rel"] = rel
		g["spec"] = spec
	return g


static func who(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


## The idea calls that wait for an answer.
static func open_ideas(sim) -> Array:
	var out: Array = []
	for e in sim.radio.open_calls():
		if String(e.kind) == "idea":
			out.append(e)
	return out


## The candidate of this kind, or {}.
static func candidate(sim, kind: String) -> Dictionary:
	for c in sim.initiative.candidates():
		if String(c.kind) == kind:
			return c
	return {}


## Wears a wall section down to `fraction` of its health.
static func wear(sim, seg_id: int, fraction: float) -> void:
	for s in sim.segments:
		if int(s.id) == seg_id:
			s.hp = s.max_hp * fraction
			sim._segment_state(s)


## Raises the best idea of this kind (the other kinds are held back for the moment by making them as good as just asked) and returns
## the call's id, or 0 when this kind is not on the table.
static func raise(sim, kind: String) -> int:
	var saved: Dictionary = sim.initiative.last_kind.duplicate()
	for k in sim.initiative.KINDS:
		if k != kind:
			sim.initiative.last_kind[k] = int(sim.day)
	var id: int = sim.initiative.propose_now()
	for k in sim.initiative.KINDS:
		if k != kind:
			if saved.has(k):
				sim.initiative.last_kind[k] = saved[k]
			else:
				sim.initiative.last_kind.erase(k)
	return id
