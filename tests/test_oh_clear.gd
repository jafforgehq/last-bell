extends "res://tests/case.gd"
## One House, WP3 (scripts/town/clearing.gd, search.gd, base.gd, sleep.gd, uses.gd and H12 in scripts/sim/interact.gd): reveal and clear the rooms of the start house,
## the claim, searching a container (and a save), sleeping. One mini town (`Helpers.town_game`); the dead are put down by closing their records in the field, the
## way the rules' own shot does it, and the avatar is put where the test needs it (the walking is the avatar's own test).

const Helpers := preload("res://tests/helpers.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


# ----------------------------------------------------------------- helpers --

func _p(sim):
	return sim.avatar.player()


func _at(sim, v: Vector2) -> void:
	var p = _p(sim)
	p.x = v.x
	p.y = v.y
	p.moving = false
	p.path = []


func _look(sim, secs: float = 0.3) -> void:
	Helpers.run(sim, secs)


## The events so far, and forget them.
func _take(sim) -> Array:
	var out: Array = sim.events.duplicate()
	sim.events.clear()
	return out


func _count(evs: Array, type: String, key: String = "", val = null) -> int:
	var n := 0
	for e in evs:
		if String(e.get("type", "")) == type and (key == "" or e.get(key) == val):
			n += 1
	return n


func _mid(d: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for t in d.tiles:
		sum += Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	return sum / float(d.tiles.size())


## The avatar goes to every doorway of the house (each reveals what is beside it).
func _visit_all(sim, h: int) -> void:
	for d in sim.houses.doors_of(h):
		_at(sim, _mid(d))
		_look(sim)


## Puts down one of the dead that is in the room (its record closed, as a shot that kills does); false when there is none.
func _kill_one(sim, room: int) -> bool:
	var f = sim.field
	for i in f.n:
		if f.status[i] == f.DORMANT and sim.houses.room_at(f.xs[i], f.ys[i]) == room:
			f.status[i] = f.KILLED
			return true
	return false


func _kill_house(sim, h: int) -> void:
	for r in sim.houses.rooms_of(h):
		while _kill_one(sim, r):
			pass


## The rooms of the house with the sides of each door, as the test works them out from the map.
func _rooms_beside(sim, d: Dictionary) -> Array:
	var out: Array = []
	for t in d.tiles:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var r: int = sim.houses.room_at(float(t.x + o.x) + 0.5, float(t.y + o.y) + 0.5)
			if r >= 0 and not out.has(r):
				out.append(r)
	return out


## The floor tile of the house nearest to `at` (as a point), for putting the avatar where a wall would be.
func _floor_near(sim, h: int, at: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for r in sim.houses.rooms_of(h):
		var rect: Rect2i = sim.houses.room(r).rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2(float(x) + 0.5, float(y) + 0.5)
				if c.distance_to(at) < best_d:
					best_d = c.distance_to(at)
					best = c
	return best


func _of_kind(sim, kind: String) -> Array:
	var out: Array = []
	for c in sim.interact.candidates():
		if String(c.kind) == kind:
			out.append(c)
	return out


## A town game with the start house explored, cleared and claimed (the dead stay asleep: nobody wakes them).
func _claimed_game() -> Dictionary:
	var g := Helpers.town_game(1, {})
	var sim = g.sim
	sim.field.pause_wake = true
	var h: int = sim.houses.start_house()
	_visit_all(sim, h)
	_kill_house(sim, h)
	_at(sim, _floor_near(sim, h, sim.base.claim_spot()))
	_look(sim)
	var r: Dictionary = sim.base.claim(h)
	check(bool(r.ok), "the cleared house is claimed (%s)" % String(r.why))
	_take(sim)
	g["house"] = h
	return g


# ------------------------------------------------------------------- tests --

func test_rooms_clear_once_and_the_house_is_clear_after_the_last_dead_one() -> void:
	var g := Helpers.town_game(1, {})
	var sim = g.sim
	var h: int = sim.houses.start_house()
	sim.field.pause_wake = true
	var rooms: Array = sim.houses.rooms_of(h)
	var with_dead: Array = []
	for r in rooms:
		if sim.houses.dead_in_room(r) > 0:
			with_dead.append(r)
	eq(sim.houses.dead_in_house(h), 3, "three dead in the start house")
	_look(sim)
	var ev := _take(sim)
	eq(_count(ev, "entered", "house", h), 1, "entered the house")
	eq(_count(ev, "room_revealed"), 1, "the room the avatar wakes in is open, no other")
	check(sim.clearing.visited(h) and sim.clearing.explored() == [h], "the house is explored")
	_visit_all(sim, h)
	ev = _take(sim)
	for r in rooms:
		check(sim.clearing.is_revealed(r), "room %d is opened by its doors" % r)
		eq(sim.clearing.is_clear(r), not with_dead.has(r), "an opened room is clear when nobody is in it")
	eq(_count(ev, "room_clear"), rooms.size() - with_dead.size(), "the empty rooms were clear on sight")
	check(not sim.clearing.house_clear(h), "not clear while a dead one is left")
	var can: Dictionary = sim.clearing.claimable(h)
	check(not bool(can.ok) and String(can.why).begins_with("There are still dead in the "), "claim refused with the room: %s" % String(can.why))
	for k in with_dead.size():
		var room: int = with_dead[k]
		while sim.houses.dead_in_room(room) > 0:
			check(_kill_one(sim, room), "a dead one to put down in room %d" % room)
			_look(sim)
			var left: int = sim.houses.dead_in_room(room)
			var e := _take(sim)
			eq(_count(e, "room_clear", "room", room), 1 if left == 0 else 0, "room_clear when the room empties, not before")
			eq(_count(e, "house_clear"), 1 if (left == 0 and k == with_dead.size() - 1) else 0, "house_clear with the last room")
	check(sim.clearing.house_clear(h), "the house is clear")
	_look(sim, 1.0)
	ev = _take(sim)
	eq(_count(ev, "room_clear") + _count(ev, "house_clear"), 0, "nothing is told twice")
	check(bool(sim.clearing.claimable(h).ok), "and it can be claimed")
	g.world.free()


func test_doors_reveal_rooms_look_in_is_an_e_use_and_entering_is_told() -> void:
	var g := Helpers.town_game(1, {})
	var sim = g.sim
	var h: int = sim.houses.start_house()
	sim.field.pause_wake = true
	_look(sim)
	_take(sim)
	var home: int = sim.houses.room_at(_p(sim).x, _p(sim).y)
	# a door of the avatar's room with a room beyond that is dark: two tiles from it, inside the room, "Look in" is offered (and is not an automatic reveal)
	var doors: Array = sim.houses.doors_of(h)
	var pick := -1
	var spot := Vector2.ZERO
	var beyond := -1
	for i in doors.size():
		var d: Dictionary = doors[i]
		var sides := _rooms_beside(sim, d)
		if bool(d.exterior) or not sides.has(home) or sides.size() < 2:
			continue
		for t in d.tiles:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var at := Vector2(float(t.x) + 0.5, float(t.y) + 0.5) + Vector2(o) * 2.0
				if pick < 0 and sim.houses.room_at(at.x, at.y) == home:
					pick = i
					spot = at
					for r in sides:
						if r != home:
							beyond = r
	check(pick >= 0, "the start room has an inner door to look through")
	_at(sim, spot)
	_look(sim)
	check(not sim.clearing.is_revealed(beyond), "two tiles from the door the room beyond is still dark")
	var doors_c := _of_kind(sim, "door")
	var mine: Dictionary = {}
	for c in doors_c:
		if String(c.id) == "d%d_%d" % [h, pick]:
			mine = c
	check(not mine.is_empty() and bool(mine.ok) and String(mine.label) == "Look in", "E offers 'Look in' at the door")
	var r: Dictionary = sim.interact.use(mine)
	check(bool(r.ok) and String(r.kind) == "door", "E looks in (through Interact.use)")
	check(sim.clearing.is_revealed(beyond), "the room beyond is open")
	eq(_count(_take(sim), "room_revealed", "room", beyond), 1, "told once")
	var again := false
	for c in _of_kind(sim, "door"):
		if String(c.id) == "d%d_%d" % [h, pick]:
			again = true
	check(not again, "no more to look at")
	# walking onto a doorway opens both sides; the avatar's own room is always open
	var front: Dictionary = {}
	for d in doors:
		if bool(d.exterior):
			front = d
	_at(sim, _mid(front))
	_look(sim)
	for r2 in _rooms_beside(sim, front):
		check(sim.clearing.is_revealed(r2), "the room behind the front door is open on the doorway")
	# out in the street: left; back in: entered, not the first time
	_take(sim)
	check(sim.clearing.inside_house() == h, "inside_house is live")
	var out_tile: Vector2i = sim.houses.house(h).door
	_at(sim, Vector2(float(out_tile.x) + 0.5, float(out_tile.y) + 0.5))
	eq(sim.clearing.inside_house(), -1, "outside the walls")
	_look(sim)
	var ev := _take(sim)
	eq(_count(ev, "left", "house", h), 1, "left told")
	_at(sim, _mid(front))
	_look(sim)
	ev = _take(sim)
	eq(_count(ev, "entered", "house", h), 1, "entered told again")
	for e in ev:
		if String(e.get("type", "")) == "entered":
			check(not bool(e.first), "but not as a first time")
	g.world.free()


func test_claim_is_refused_with_a_reason_then_installs_the_base_in_two_seconds() -> void:
	var g := Helpers.town_game(1, {})
	var sim = g.sim
	var h: int = sim.houses.start_house()
	sim.field.pause_wake = true
	_visit_all(sim, h)
	var spot: Vector2 = _floor_near(sim, h, sim.base.claim_spot())
	check(spot.distance_to(sim.base.claim_spot()) <= 2.2, "a floor tile is within reach of the claim spot")
	_at(sim, spot)
	_look(sim)
	var refused: Dictionary = sim.base.claim(h)
	check(not bool(refused.ok) and String(refused.why).begins_with("There are still dead in the "), "refused while a dead one is left: %s" % String(refused.why))
	var cands := _of_kind(sim, "claim")
	check(cands.size() == 1 and not bool(cands[0].ok), "the claim is listed with its reason")
	var ur: Dictionary = sim.interact.use(cands[0])
	check(not bool(ur.ok) and String(ur.why) == String(refused.why), "and E says why")
	_kill_house(sim, h)
	_look(sim)
	cands = _of_kind(sim, "claim")
	check(cands.size() == 1 and bool(cands[0].ok) and String(cands[0].label) == "Claim this house", "once clear, 'Claim this house'")
	# a stub layout with one plot and one station, to see the hooks are called
	# (laid round the claim spot: the town makes its houses anywhere, the stub's lot goes where the avatar stands)
	var made := {"n": 0}
	var before_spawns: Array = sim.spawns.duplicate()
	var cs: Vector2 = sim.base.claim_spot()
	var plot := Rect2i(Vector2i(cs) - Vector2i(10, 8), Vector2i(20, 16))
	sim.base.maker = func(_town, house_id):
		made.n += 1
		return {"version": 1, "house": house_id, "kind": "small", "front": "S", "plot": plot, "center": cs, "yard_middle": cs + Vector2(0, 4),
			"compound": Rect2(Vector2(plot.position) - Vector2(3, 3), Vector2(plot.size) + Vector2(6, 6)), "claim_spot": sim.base.claim_spot(), "interior": [{"id": "bed", "kind": "bed", "pos": cs + Vector2(-2.5, -2.5), "room": 0, "face": "S"}],
			"stations": [], "rest": {}, "posts": [], "doors": [], "slots": [], "plots": [], "buildings": [], "spawns": [Vector2(40.5, 12.5), Vector2(8.5, 50.5)], "ring": {"free": 1, "blocked": 0}}
	var started: Dictionary = sim.interact.use(cands[0])
	check(bool(started.ok) and bool(started.get("session", false)), "E begins the claim as a session")
	eq(String(sim.uses.progress().label), "Claiming", "the ring has its label")
	_look(sim, 1.0)
	check(not sim.base.claimed, "not yet after a second")
	near(float(sim.uses.progress().t), 1.0, 0.1, "the ring runs")
	near(float(sim.uses.progress().of), 2.0, 0.001, "of two seconds")
	_look(sim, 1.2)
	check(sim.base.claimed and sim.base.house == h, "claimed after two seconds")
	eq(made.n, 1, "the layout was made once (the maker's)")
	eq(String(sim.uses.progress().label), "", "the session is over")
	var ev := _take(sim)
	eq(_count(ev, "claimed", "house", h), 1, "the claim is told once")
	check(_count(ev, "banner", "text", "This house is yours") == 1, "and the banner")
	check(sim.spawns.size() == 2 and sim.spawns == sim.base.spawns() and sim.spawns != before_spawns, "the night's entrances are the layout's")
	check(sim.base.compound().has_point(Vector2(_p(sim).x, _p(sim).y)) and sim.base.at_base(_p(sim)), "the avatar is at the base")
	eq(sim.base.props().size(), 1, "the props to draw")
	check(not bool(sim.base.claim(h).ok), "a second claim is refused")
	_look(sim, 1.0)
	eq(_count(_take(sim), "claimed"), 0, "and told no more")
	g.world.free()


func test_search_puts_the_loot_in_the_stores_and_the_looted_flag_survives_a_save() -> void:
	var g := _claimed_game()
	var sim = g.sim
	var h: int = g.house
	var cont: Dictionary = sim.houses.containers_of(h)[0]
	var id := String(cont.id)
	var before: Dictionary = sim.stock.duplicate()
	_at(sim, Vector2(cont.pos))
	_look(sim)
	var cs := _of_kind(sim, "container")
	check(cs.size() == 1 and String(cs[0].id) == id and bool(cs[0].ok), "the container is offered")
	_at(sim, Vector2(cont.pos) + Vector2(1.5, 0.0))
	check(_of_kind(sim, "container").is_empty(), "not from 1.5 tiles")
	_at(sim, Vector2(cont.pos))
	var r: Dictionary = sim.interact.use(cs[0])
	check(bool(r.ok) and bool(r.get("session", false)), "E begins the search")
	_look(sim, 2.0)
	check(not sim.search.is_looted(id), "not done after two seconds")
	near(float(sim.search.state(id).progress), 0.5, 0.1, "halfway")
	_look(sim, 2.2)
	check(sim.search.is_looted(id), "looted after four")
	for k in cont.loot:
		near(float(sim.stock[k]) - float(before[k]), float(cont.loot[k]), 0.001, "the loot of %s is in the stock" % String(k))
	var ev := _take(sim)
	eq(_count(ev, "searched", "container", id), 1, "told once")
	check(_of_kind(sim, "container").is_empty(), "nothing more to search")
	var stash := _of_kind(sim, "stash")
	_at(sim, Vector2(sim.base.prop("stash").pos))
	stash = _of_kind(sim, "stash")
	check(stash.size() == 1 and String(sim.interact.use(stash[0]).line).begins_with("Stores: "), "the stash tells the stores")
	# a save, a new game, a load
	var data: Dictionary = SaveGame.to_dict(sim)
	var g2 := Helpers.town_game(1, {})
	var sim2 = g2.sim
	check(SaveGame.apply(sim2, data), "the save is read")
	check(sim2.search.is_looted(id), "the looted container is looted after a load")
	check(sim2.base.claimed and sim2.base.house == h and sim2.base.props().size() == 4, "the base is claimed after a load, with its props")
	check(sim2.clearing.house_clear(h) and sim2.clearing.is_revealed(sim2.houses.rooms_of(h)[0]), "the cleared house is cleared after a load")
	eq(sim2.spawns, sim2.base.spawns(), "the spawns are the base's")
	g2.world.free()
	g.world.free()


func test_sleep_runs_to_dawn_and_is_refused_or_broken_by_the_dead() -> void:
	var g := _claimed_game()
	var sim = g.sim
	sim.min_per_sec = 2.0
	sim.waves.enabled = false
	var bed: Vector2 = sim.base.prop("bed").pos
	_at(sim, bed)
	sim.sleep.budget_us = 0
	# by day: too early
	check(not bool(sim.sleep.can_sleep().ok), "not by day")
	Helpers.at(sim, 1, 21.0)
	_look(sim)
	var bd := _of_kind(sim, "bed")
	check(bd.size() == 1 and String(bd[0].label) == "Sleep until dawn" and bool(bd[0].ok), "the bed is offered at 21:00")
	# a dead one awake and after somebody 15 tiles off refuses (one that only stands 15 tiles off does not: it is put back to sleep as the avatar lies down)
	var hs_mid: Vector2 = sim.base.center()
	var z = sim.spawn(hs_mid.x + 15.0, hs_mid.y, "chase")
	var no: Dictionary = sim.sleep.begin()
	check(not bool(no.ok) and String(no.why).contains("dead"), "refused with a dead one 15 tiles away: %s" % String(no.why))
	check(not sim.sleep.active(), "and not asleep")
	# one that comes in the night wakes the avatar
	z.state = "dying"
	z.hp = 0.0
	sim.zombies.clear()
	var minutes_asked: float = float(sim.sleep.begin().minutes)
	near(minutes_asked, 570.0, 1.0, "21:00 to 06:30 is nine and a half hours")
	check(sim.sleep.active(), "asleep")
	for i in 40:
		sim.sleep.advance()
	check(sim.sleep.active(), "still asleep in the small hours")
	var arrival = sim.spawn(bed.x + 10.0, bed.y, "wander")
	sim.sleep.advance()
	check(not sim.sleep.active(), "woken by the dead one at 10 tiles")
	var ev := _take(sim)
	var woke: Array = []
	for e in ev:
		if String(e.get("type", "")) == "sleep":
			woke.append(e)
	check(woke.size() == 2 and bool(woke[0].on) == true and not bool(woke[1].on) and String(woke[1].why) == "Something is near", "told: on, then off with the reason")
	arrival.state = "dying"
	arrival.hp = 0.0
	sim.zombies.clear()
	# a quiet night to dawn: the clock ends at 06:30, the stores are eaten for the hours
	Helpers.at(sim, 1, 21.0)
	sim.supplies.sources_day = 1
	var hunger0: float = float(_p(sim).hunger_h)
	var thirst0: float = float(_p(sim).thirst_h)
	check(bool(sim.sleep.begin().ok), "asleep again at 21:00")
	# (this time the town's own step drives it: `update` calls `advance`, a nested step of the fast-forward finds it busy)
	sim.sleep.budget_us = 10000
	var guard := 0
	while sim.sleep.active() and guard < 3000:
		Helpers.run(sim, 0.1)
		guard += 1
	check(not sim.sleep.active(), "awake")
	near(sim.hour, 6.5, 0.05, "at 06:30")
	eq(sim.phase, "day", "the day has begun")
	near(float(_p(sim).hunger_h) - hunger0, 9.5, 0.2, "the hours were lived through: hunger grew by nine and a half")
	near(float(_p(sim).thirst_h) - thirst0, 9.5, 0.2, "and thirst")
	var last: Dictionary = _take(sim).filter(func(e): return String(e.get("type", "")) == "sleep").back()
	check(not bool(last.on) and String(last.why) == "dawn", "told: dawn")
	g.world.free()
