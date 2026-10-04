extends "res://tests/case.gd"
## Round 22, GATE-SIM (scripts/sim/gate.gd): what the real gate does to the world. The walking grids and the deck's face under the bridge as it
## opens and shuts, people through it, the dead (they walk in through an open gate, they claw at a shut one as they always did, they are not let
## to stand in the way of a closing one), the section's health left alone, and the trips: a car on its drive out and in, a party on foot and a caller
## at 07:00, each of which waits for a gate that is held shut, with the reason in the News, and none of which is ever shut on.
## (The rules by themselves, the hand, the bell and the call are tests/test_gate_rules.gd's.)

const Helpers := preload("res://tests/helpers.gd")
const Gate := preload("res://scripts/sim/gate.gd")
const Convoy := preload("res://scripts/sim/convoy.gd")

const DT := 1.0 / 30.0
const COLS := [37, 38, 39, 40]
## The rows of the mouth that are solid while the gate is shut: the wall's three and the deck's face under the bridge.
const ROWS := [15, 16, 17, 19, 20]
## Somewhere in the yard and somewhere in the street.
const YARD := Vector2(39.5, 24.5)
const STREET := Vector2(39.5, 11.0)


# ----------------------------------------------------------------- helpers --

func _game(crew: int = 5) -> Dictionary:
	var g := Helpers.avatar_game(3, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.no_work(sim)
	Helpers.at(sim, 1, 9.0)
	sim.events.clear()
	sim.radio.news.clear()
	_put(_p(sim, "ruth"), Vector2(50.5, 30.5))
	_put(_p(sim, "dez"), Vector2(44.5, 30.5))
	g["ruth"] = _p(sim, "ruth")
	g["dez"] = _p(sim, "dez")
	return g


func _p(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _put(p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.path = []
	p.goal_key = ""
	p.moving = false


func _go(sim, seconds: float) -> void:
	for i in int(round(seconds * 30.0)):
		sim.update(DT)


## Steps until `cond` holds; the steps it took, or -1 when it did not within `limit` steps.
func _until(sim, cond: Callable, limit: int = 3000) -> int:
	var n := 0
	while not cond.call() and n < limit:
		sim.update(DT)
		n += 1
	return n if cond.call() else -1


func _solid(g: Dictionary, grid: String, col: int, row: int) -> bool:
	return int(g.world.get(grid)[row * g.world.W + col]) != 0


## Every tile of the mouth is `shut` (solid on both walking grids) or all open.
func _mouth_is(g: Dictionary, shut: bool) -> bool:
	for c in COLS:
		for r in ROWS:
			if _solid(g, "solid_p", c, r) != shut or _solid(g, "solid_z", c, r) != shut:
				return false
	return true


## Whether a path (waypoints) passes through a tile of the mouth (the compound is not sealed: the catwalk's west end lets a way round, so
## a way out is looked for through the gateway itself).
func _through_mouth(from: Vector2, path: Array) -> bool:
	for i in path.size():
		var a: Vector2 = path[i]
		var b: Vector2 = path[i - 1] if i > 0 else from
		for k in 11:
			var pt: Vector2 = b.lerp(a, float(k) / 10.0)
			if COLS.has(floori(pt.x)) and ROWS.has(floori(pt.y)):
				return true
	return false


func _segment(sim, id: int):
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


func _night(sim, day: int, hour: float) -> void:
	Helpers.at(sim, day, hour)
	_go(sim, 0.05)
	sim.events.clear()
	sim.radio.news.clear()


func _news(sim) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == "gate":
			out.append(String(e.text))
	return out


## The gate was opened by hand in the dark and the dead came near: the call is raised; the avatar answers "keep it open".
func _keep_open(sim) -> void:
	_go(sim, 0.1)
	for c in sim.radio.open_calls():
		if String(c.kind) == "gate":
			check(sim.radio.answer(int(c.id), "keep"), "kept open")


func _hold_at(p, at: Vector2) -> void:
	_put(p, at)
	p.drafted = true
	p.order = Vector3(at.x, at.y, 0.0)


# ------------------------------------------------------------------ the grids --

func test_the_mouth_is_solid_while_shut_walkable_from_half_and_solid_again() -> void:
	var g := _game()
	var sim = g.sim
	check(_mouth_is(g, true), "shut: the map's own")
	check(g.world.deck_face_tiles.has(19 * g.world.W + 38) and g.world.deck_face_tiles.has(20 * g.world.W + 38), "the deck's face is there under the bridge")
	var posts := [36, 41]
	for c in posts:
		for r in [15, 16, 17]:
			check(_solid(g, "solid_p", c, r), "a post's column %d stays wall" % c)
	sim.gate.request(true)
	_go(sim, 0.9)
	check(sim.gate.open < 0.5 and _mouth_is(g, true), "not yet half: still solid")
	_go(sim, 0.3)
	check(sim.gate.open > 0.5 and _mouth_is(g, false), "past half: walkable on both grids")
	check(not g.world.deck_face_tiles.has(19 * g.world.W + 38) and not g.world.deck_face_tiles.has(20 * g.world.W + 38), "the deck's face is not there: a shot goes through the opening")
	for c in posts:
		for r in [15, 16, 17]:
			check(_solid(g, "solid_p", c, r), "the post's column %d stays wall when open" % c)
	for c in COLS:
		check(_solid(g, "solid_p", c, 14) == false and _solid(g, "solid_p", c, 18) == false and _solid(g, "solid_p", c, 21) == false, "the ground at either end is open")
	check(g.world.deck_tiles.has(18 * g.world.W + 38), "the catwalk's row is deck either way")
	sim.gate.request(false)
	_go(sim, 2.3)
	eq(sim.gate.open, 0.0, "shut")
	check(_mouth_is(g, true), "solid again")
	check(g.world.deck_face_tiles.has(19 * g.world.W + 38) and g.world.deck_face_tiles.has(20 * g.world.W + 38), "and the deck's face is back")
	g.world.free()


func test_a_way_through_for_people_and_the_dead_only_while_it_is_open() -> void:
	var g := _game()
	var sim = g.sim
	var out_p: Array = sim.path_p.find(g.world.solid_p, YARD.x, YARD.y, STREET.x, STREET.y)
	var in_z: Array = sim.path_z.find(g.world.solid_z, STREET.x, STREET.y, YARD.x, YARD.y)
	check(not _through_mouth(YARD, out_p), "no way out of the yard for people through a shut gate")
	check(not _through_mouth(STREET, in_z), "nor in for the dead")
	sim.gate.request(true)
	_go(sim, 2.2)
	out_p = sim.path_p.find(g.world.solid_p, YARD.x, YARD.y, STREET.x, STREET.y)
	in_z = sim.path_z.find(g.world.solid_z, STREET.x, STREET.y, YARD.x, YARD.y)
	check(_through_mouth(YARD, out_p), "a way out through the gateway when it is open")
	check(_through_mouth(STREET, in_z), "and in for the dead")
	sim.gate.request(false)
	_go(sim, 2.3)
	out_p = sim.path_p.find(g.world.solid_p, YARD.x, YARD.y, STREET.x, STREET.y)
	in_z = sim.path_z.find(g.world.solid_z, STREET.x, STREET.y, YARD.x, YARD.y)
	check(not _through_mouth(YARD, out_p), "shut again: not through it")
	check(not _through_mouth(STREET, in_z), "for the dead too")
	g.world.free()


func test_a_person_walks_out_through_an_open_gate_and_not_through_a_shut_one() -> void:
	var g := _game()
	var sim = g.sim
	sim.order_move(g.dez, STREET.x, STREET.y)
	var through := false
	for i in 900:
		sim.update(DT)
		if COLS.has(floori(g.dez.x)) and ROWS.has(floori(g.dez.y)):
			through = true
	check(not through, "Dez does not go through a shut gate (he goes the long way round, or nowhere)")
	g.dez.drafted = false
	g.dez.order = null
	_put(g.dez, YARD)
	sim.gate.request(true)
	_go(sim, 2.2)
	check(sim.order_move(g.dez, STREET.x, STREET.y), "ordered through the open gate")
	var n := _until(sim, func(): return g.dez.y < 14.0, 900)
	check(n >= 0, "he walks out through the gateway (y=%f)" % g.dez.y)
	check(n < 500, "straight out: %d steps" % n)
	g.world.free()


func test_a_walker_who_was_on_a_path_through_a_gate_that_shut_is_asked_again() -> void:
	var g := _game()
	var sim = g.sim
	sim.gate.request(true)
	_go(sim, 2.2)
	sim.order_move(g.dez, STREET.x, STREET.y)
	_go(sim, 1.0)
	check(g.dez.path.size() > 0, "he has a way")
	var shut: Dictionary = sim.gate.request(false)
	if bool(shut.ok):
		_go(sim, 2.5)
	check(sim.gate.open == 0.0 or g.dez.y < 15.0 or sim.gate.is_passable(), "it either waited for him or he was already out: %f" % sim.gate.open)
	# whoever was on the way: nothing is ever inside a solid tile of the mouth
	for p in sim.people:
		if sim.gate.open == 0.0:
			check(not (COLS.has(floori(p.x)) and ROWS.has(floori(p.y))), "%s is not inside the shut gate" % p.first)
	g.world.free()


# ------------------------------------------------------------------- the dead --

func test_the_dead_claw_at_a_shut_gate_as_they_always_did() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim, 2, 22.0)
	var seg = _segment(sim, 2)
	var before: float = seg.hp
	var dead: Array = Helpers.attack(sim, 2, 3)
	eq(dead.size(), 3, "three at the gate")
	for z in dead:
		z.hp = 1.0e9
	_go(sim, 12.0)
	check(seg.hp < before - 5.0, "the gate is torn at: %f of %f" % [seg.hp, before])
	var clawing := 0
	for z in dead:
		if String(z.state) == "attack":
			clawing += 1
	eq(clawing, 3, "they stay at it")
	check(not sim.gate.lets_dead_in(), "it is a wall")
	g.world.free()


func test_the_dead_who_come_to_an_open_gate_walk_in_and_do_not_claw_it() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim, 2, 22.0)
	var seg = _segment(sim, 2)
	var before: float = seg.hp
	var dead: Array = Helpers.attack(sim, 2, 3)
	for z in dead:
		z.hp = 1.0e9
	check(bool(sim.gate.request(true).ok), "opened by hand in the dark")
	_keep_open(sim)
	var n := _until(sim, func(): return sim.gate.lets_dead_in(), 200)
	check(n >= 0, "it is open")
	_go(sim, 0.1)
	var hp_open: float = seg.hp    # (they clawed at it while the leaves were on the move: from here it is open)
	check(hp_open > before - 20.0, "(a second's claws at most: %f)" % hp_open)
	for z in dead:
		check(String(z.state) != "attack", "nobody claws at an open gate: %s" % String(z.state))
		check(z.slot == null, "they have let go of their places")
	check(sim.yard_open(), "an open gate is a way into the yard, as a section that fell")
	var got := _until(sim, func(): return dead.all(func(z): return z.y > 17.9), 1800)
	check(got >= 0, "they walk in through the gateway, past the wall: %s" % str(dead.map(func(z): return snappedf(z.y, 0.1))))
	eq(seg.hp, hp_open, "and the gate took no harm from then on")
	eq(int(seg.state), 0, "and has the state it had")
	g.world.free()


func test_a_walker_of_the_streets_comes_to_the_yard_through_an_open_gate_and_stays_out_of_a_shut_one() -> void:
	# open: it is drawn in
	var g := _game()
	var sim = g.sim
	_night(sim, 2, 22.0)
	sim.gate.request(true)
	_go(sim, 2.2)
	var z = sim.spawn(39.5, 8.0, "approach")
	z.hp = 1.0e9
	_keep_open(sim)
	var n := _until(sim, func(): return z.y > 17.9, 2400)
	check(n >= 0, "an approaching walker is through the wall (y=%f, %s)" % [z.y, String(z.state)])
	g.world.free()
	# shut: it is not
	var h := _game()
	var sim2 = h.sim
	_night(sim2, 2, 22.0)
	var z2 = sim2.spawn(39.5, 8.0, "approach")
	z2.hp = 1.0e9
	_go(sim2, 40.0)
	check(z2.y < 17.5 and String(z2.state) != "breach", "at a shut gate it is at the wall, not in the yard (y=%f, %s)" % [z2.y, String(z2.state)])
	h.world.free()


func test_a_gate_shut_again_sends_the_dead_outside_back_to_the_wall() -> void:
	var g := _game()
	var sim = g.sim
	_night(sim, 2, 22.0)
	sim.gate.request(true)
	_go(sim, 2.2)
	var z = sim.spawn(39.5, 6.0, "approach")
	z.hp = 1.0e9
	_keep_open(sim)
	_go(sim, 2.0)
	eq(String(z.state), "breach", "it is in the breach rules while the gate stands open")
	check(z.y < 15.0, "(still outside)")
	z.stagger = 0.0
	check(bool(sim.gate.request(false).ok), "shut now")
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "shut")
	_go(sim, 3.0)
	check(String(z.state) != "breach", "a walker outside a shut gate is at the wall again: %s" % String(z.state))
	g.world.free()


func test_nothing_assigns_a_place_at_an_open_gate() -> void:
	var g := _game()
	var sim = g.sim
	sim.gate.request(true)
	_go(sim, 2.2)
	for i in 40:
		var z = sim.spawn(39.5, 10.0 + float(i % 3), "approach")
		var seg = null
		if sim.assign_slot(z, null):
			seg = z.slot.seg
		check(seg == null or int(seg.id) != 2, "a place of the open gate is never given")
		sim.zombies.erase(z)
		if z.slot != null:
			z.slot.who = null
	var gate = _segment(sim, 2)
	var z2 = sim.spawn(39.5, 10.0, "approach")
	check(not sim.assign_slot(z2, gate), "not even when asked for it by name")
	sim.gate.request(false)
	_go(sim, 2.3)
	var z3 = sim.spawn(39.5, 10.0, "approach")
	check(sim.assign_slot(z3, gate), "a shut gate has places again")
	g.world.free()


func test_a_closing_gate_waits_for_the_dead_in_it_and_says_who() -> void:
	var g := _game()
	var sim = g.sim
	sim.gate.request(true)
	_go(sim, 2.2)
	var z = sim.spawn(39.5, 16.5, "breach")
	z.hp = 1.0e9
	z.stagger = 1000.0    # (it stands where it is)
	var r: Dictionary = sim.gate.request(false)
	check(not bool(r.ok), "refused")
	eq(String(r.why), "The dead are in the gateway: put them down first", "with the reason")
	# the bell (or the alarm) shuts it when it can
	sim.gate.shut_for("dusk")
	for i in 180:
		z.stagger = 1000.0    # (it stands where it is: nobody shoots it into moving)
		sim.update(DT)
	eq(sim.gate.open, 1.0, "the leaves wait for it")
	check(_news(sim).has("The gate cannot shut yet"), "and the News says so: %s" % str(_news(sim)))
	sim.zombies.erase(z)    # (put down)
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "once it is gone the gate shuts")
	g.world.free()


func test_the_gates_health_and_state_are_its_own_whatever_it_is_doing() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _segment(sim, 2)
	sim._damage_segment(seg, 100.0)    # (to 120 of 220: state 1)
	var hp: float = seg.hp
	var st: int = seg.state
	check(st == 1, "worn: state %d" % st)
	sim.gate.request(true)
	_go(sim, 2.5)
	check(sim.gate.is_passable(), "a worn gate opens")
	sim.gate.request(false)
	_go(sim, 2.5)
	eq(seg.hp, hp, "its health is what it was")
	eq(int(seg.state), st, "and its state")
	check(not sim.gate.is_passable(), "a worn gate shuts")
	g.world.free()


func test_a_gate_the_dead_have_brought_down_is_a_heap_and_mending_it_gives_a_shut_gate() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _segment(sim, 2)
	sim.gate.request(true)
	_go(sim, 2.5)
	sim._damage_segment(seg, 9999.0)    # (to 0: it falls even with the gate open)
	_go(sim, 0.2)
	check(sim.gate.wrecked(), "down")
	eq(sim.gate.open, 0.0, "the leaves are gone")
	check(sim.gate.is_passable(), "rubble to pass")
	for c in COLS:
		for r in [15, 16, 17]:
			check(not _solid(g, "solid_p", c, r), "the wreck's own opening: %d,%d" % [c, r])
		for r in [19, 20]:
			check(_solid(g, "solid_p", c, r), "the deck's face is not the wreck's: %d,%d" % [c, r])
	sim._repair_segment(seg, 9999.0)
	_go(sim, 0.2)
	check(not sim.gate.wrecked(), "mended")
	check(_mouth_is(g, true), "a shut gate again, solid all through")
	check(bool(sim.gate.request(true).ok), "and it can be worked")
	g.world.free()


# ------------------------------------------------------------------------ trips --

## A town game (a small start) at 07:00 with a sedan in the motor pool and Dez and Marcus ready to go; Ruth is the player.
func _trip_game() -> Dictionary:
	var g := _game(5)
	var sim = g.sim
	sim.zombies.clear()
	sim.vehicles.fuel = 60.0
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	Helpers.at(sim, 3, 7.0)
	sim.supplies.sources_day = 3
	var v: Dictionary = sim.vehicles.add("sedan")
	g["vehicle"] = String(v.id)
	g["crew"] = [_p(sim, "dez"), _p(sim, "marcus")]
	sim.events.clear()
	return g


func _party(sim) -> Dictionary:
	return sim.scavenge.parties[0] if not sim.scavenge.parties.is_empty() else {}


func _state(sim) -> String:
	return String(_party(sim).get("state", "done"))


## Everyone of the party at their door, so that a test need not wait for the walk.
func _at_doors(sim, party: Dictionary) -> void:
	for id in party.members:
		var v: Dictionary = sim.vehicles.vehicle(String(party.vehicle))
		var seat := int(party.seats[id])
		var at: Vector2 = Convoy.door_spot(int(v.spot), String(v.kind), sim.vehicles.seat_door(String(v.kind), seat, int(v.spot)))
		_put(_p(sim, String(id)), at)


## The car's nose and where it is on its drive: {"nose": Vector2, "pos": Vector2}.
func _car(sim, party: Dictionary) -> Dictionary:
	if party.is_empty() or not party.has("drive_t"):
		return {"pos": Vector2.ZERO, "nose": Vector2.ZERO, "tail": Vector2.ZERO}
	var v: Dictionary = sim.vehicles.vehicle(String(party.vehicle))
	var out := String(party.state) == "driving_out"
	var route: Array = Convoy.route(int(v.spot), "out" if out else "in")
	var at: Dictionary = Convoy.pose(route, float(party.drive_t) / float(party.drive_len))
	var half := float(sim.vehicles.kind(String(v.kind)).h) / 2.0
	return {"pos": at.pos, "nose": at.pos + Vector2.from_angle(float(at.heading)) * half, "tail": at.pos - Vector2.from_angle(float(at.heading)) * half}


func test_a_car_waits_at_a_gate_held_shut_and_goes_when_it_is_let_go() -> void:
	var g := _trip_game()
	var sim = g.sim
	check(sim.scavenge.send(g.crew, "houses", "loot", g.vehicle), "the party goes")
	var party := _party(sim)
	check(sim.gate.hold("shut"), "the avatar holds the gate shut")
	_at_doors(sim, party)
	var n := _until(sim, func(): return _state(sim) == "driving_out", 1500)
	check(n >= 0, "they board and the car sets off (%s)" % _state(sim))
	_go(sim, 8.0)
	eq(_state(sim), "driving_out", "the car is still on the apron: it waits")
	var car := _car(sim, _party(sim))
	check(car.nose.y > 20.9, "its nose has not met the bridge: y=%f" % car.nose.y)
	check(car.nose.y < 23.5, "but it has driven up to it: y=%f" % car.nose.y)
	eq(sim.gate.open, 0.0, "the gate is shut")
	check(_news(sim).has("The sedan waits to go out: the gate is shut"), "the News says why: %s" % str(_news(sim)))
	eq(sim.gate.who_blocks(), [], "(it is not in the gateway)")
	# let go: the keeper opens it and the car goes through
	check(sim.gate.hold(""), "let go")
	var crossed := false
	var open_when_in := true
	for i in 1500:
		sim.update(DT)
		if _state(sim) != "driving_out":
			break
		if sim.gate.who_blocks().has("The sedan"):
			crossed = true
			if not sim.gate.is_passable():
				open_when_in = false
	check(crossed, "the car went through the gateway")
	check(open_when_in, "and the gate was open the whole time it was in it")
	eq(_state(sim), "away", "the trip's hours begin")
	_go(sim, 8.0)
	eq(sim.gate.open, 0.0, "and the gate shut behind it")
	g.world.free()


func test_a_car_coming_home_waits_outside_a_gate_held_shut_and_is_let_in() -> void:
	var g := _trip_game()
	var sim = g.sim
	check(sim.scavenge.send(g.crew, "houses", "loot", g.vehicle), "the party goes")
	_at_doors(sim, _party(sim))
	var n := _until(sim, func(): return _state(sim) == "away", 3000)
	check(n >= 0, "it is out (%s)" % _state(sim))
	_go(sim, 6.0)
	eq(sim.gate.open, 0.0, "the gate is shut behind it")
	check(sim.gate.hold("shut"), "held shut")
	_party(sim).return_at = sim.clock_min    # (due)
	n = _until(sim, func(): return _state(sim) == "driving_in", 200)
	check(n >= 0, "the car drives in")
	_go(sim, 10.0)
	eq(_state(sim), "driving_in", "it waits")
	var car := _car(sim, _party(sim))
	check(car.nose.y < 15.0, "outside, with its nose short of the wall: y=%f" % car.nose.y)
	check(car.nose.y > 11.0, "(it has come to it)")
	check(_news(sim).has("The sedan waits outside: the gate is shut"), "the News: %s" % str(_news(sim)))
	check(sim.gate.hold(""), "let go")
	n = _until(sim, func(): return _state(sim) == "unloading", 2500)
	check(n >= 0, "it comes in and parks (%s)" % _state(sim))
	g.world.free()


func test_a_car_with_the_avatar_away_is_let_through_a_gate_held_shut() -> void:
	var g := _trip_game()
	var sim = g.sim
	check(sim.scavenge.send(g.crew, "houses", "loot", g.vehicle), "the party goes")
	_at_doors(sim, _party(sim))
	_until(sim, func(): return _state(sim) == "away", 3000)
	_go(sim, 6.0)
	sim.gate.hold("shut")
	g.ruth.away = {"kind": "party"}    # (the avatar is in the car or elsewhere: nobody is at the lever)
	_party(sim).return_at = sim.clock_min
	var n := _until(sim, func(): return _state(sim) == "unloading", 3000)
	check(n >= 0, "it was let in (%s)" % _state(sim))
	g.ruth.away = null
	g.world.free()


func test_a_party_on_foot_asks_for_the_gate_and_waits_at_one_held_shut() -> void:
	var g := _trip_game()
	var sim = g.sim
	var dez = g.dez
	_put(dez, Vector2(44.0, 18.5))    # (on the catwalk, a few tiles from the gate post)
	check(sim.scavenge.send([dez], "houses", "loot", ""), "he goes on foot")
	check(sim.gate.hold("shut"), "the avatar holds the gate shut")
	_go(sim, 25.0)
	eq(_state(sim), "out", "he waits at the gate")
	check(dez.away == null, "he is still to be seen")
	check(Vector2(dez.x, dez.y).distance_to(Vector2(39.0, 18.9)) < 3.0, "close to it: %f,%f" % [dez.x, dez.y])
	eq(sim.gate.open, 0.0, "shut")
	check(_news(sim).has("Dez waits to go out: the gate is shut"), "the News says why: %s" % str(_news(sim)))
	check(sim.gate.hold(""), "let go")
	var n := _until(sim, func(): return _state(sim) == "away", 600)
	check(n >= 0, "he goes through once it opens (%s)" % _state(sim))
	check(dez.away != null, "and is gone")
	_go(sim, 8.0)
	eq(sim.gate.open, 0.0, "the gate shuts behind him")
	g.world.free()


func test_a_party_on_foot_that_asks_finds_the_gate_open_without_waiting() -> void:
	var g := _trip_game()
	var sim = g.sim
	var dez = g.dez
	_put(dez, Vector2(46.0, 18.5))
	check(sim.scavenge.send([dez], "houses", "loot", ""), "he goes on foot")
	var n := _until(sim, func(): return _state(sim) == "away", 900)
	check(n >= 0, "he is through (%s)" % _state(sim))
	check(_news(sim).is_empty(), "nothing to tell: the gate opened as he came")
	g.world.free()


func test_a_party_on_foot_comes_home_through_the_gate_and_waits_outside_one_held_shut() -> void:
	var g := _trip_game()
	var sim = g.sim
	var dez = g.dez
	_put(dez, Vector2(46.0, 18.5))
	check(sim.scavenge.send([dez], "houses", "loot", ""), "he goes on foot")
	_until(sim, func(): return _state(sim) == "away", 900)
	_go(sim, 8.0)
	sim.gate.hold("shut")
	_party(sim).return_at = sim.clock_min
	_go(sim, 6.0)
	eq(_state(sim), "away", "he waits outside")
	check(dez.away != null, "still out")
	check(_news(sim).has("Dez waits outside: the gate is shut"), "the News: %s" % str(_news(sim)))
	sim.gate.hold("")
	var n := _until(sim, func(): return sim.scavenge.parties.is_empty(), 600)
	check(n >= 0, "once it is open he is home")
	check(dez.away == null, "and to be seen")
	g.world.free()


# ---------------------------------------------------------------------- callers --

func test_a_caller_at_seven_waits_at_a_gate_held_shut_and_comes_in_when_it_opens() -> void:
	var g := _game(3)
	var sim = g.sim
	Helpers.at(sim, 3, 6.9)
	sim.supplies.sources_day = 3
	var def: Dictionary = sim.recruits.queue.pop_front()
	sim.recruits.incoming.append({"def": def, "day": 3})
	sim.gate.hold("shut")
	var crew: int = sim.people.size()
	_go(sim, 20.0)    # (a game hour is 20 seconds: past 07:00)
	check(sim.hour >= 7.0, "it is past seven")
	eq(sim.people.size(), crew, "nobody came in")
	eq(sim.recruits.incoming.size(), 1, "the caller is at the gate")
	check(_news(sim).has("%s is outside the gate: the gate is shut" % String(def.name)), "the News says why: %s" % str(_news(sim)))
	sim.gate.hold("")
	var n := _until(sim, func(): return sim.people.size() > crew, 300)
	check(n >= 0, "they come in once it is open")
	eq(sim.recruits.incoming.size(), 0, "no longer outside")
	_go(sim, 8.0)
	eq(sim.gate.open, 0.0, "and the gate shuts behind them")
	g.world.free()


func test_a_caller_comes_in_at_seven_through_the_gate_the_keeper_opens() -> void:
	var g := _game(3)
	var sim = g.sim
	Helpers.at(sim, 3, 7.0)
	sim.supplies.sources_day = 3
	var def: Dictionary = sim.recruits.queue.pop_front()
	sim.recruits.incoming.append({"def": def, "day": 3})
	var crew: int = sim.people.size()
	var n := _until(sim, func(): return sim.people.size() > crew, 300)
	check(n >= 0 and n < 120, "they come in as the gate opens (steps: %d)" % n)
	check(_news(sim).is_empty(), "with nothing to tell")
	g.world.free()
