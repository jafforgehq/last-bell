extends "res://tests/case.gd"
## Fix round 3, issue 3: "you can stand on the section while you are below on the door", "you can climb from the opening door to the guarding post
## above", "you can jump off from the guard post or on". The ground and the decks (the catwalk, the side walkways, the towers) are two levels
## crossed at a ladder only (scripts/sim/levels.gd): the corner towers' outer sides are shut, the bridge over the gateway is the deck for the one who came
## onto it along the catwalk and the passage for the one who came along the passage (so the ground cannot step up onto the catwalk beside it and the deck cannot
## step down into the passage), a person in the passage is not on the deck and is in the gateway, one on the bridge is not, and a post on a deck is taken from
## that deck only.

const Helpers := preload("res://tests/helpers.gd")

const DT := 1.0 / 30.0


func _game() -> Dictionary:
	var g := Helpers.avatar_game(3, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.no_work(sim)
	Helpers.at(sim, 1, 9.0)
	sim.events.clear()
	for p in sim.people:
		if not p.player:
			_put(p, Vector2(50.5, 40.5))
	g["me"] = sim.avatar.player()
	g["dez"] = _person(sim, "dez")
	sim.update(DT)
	return g


func _person(sim, id: String):
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


func _open_gate(sim) -> void:
	sim.gate.request(true, "player")
	for i in 90:
		sim.update(DT)


## The avatar's hands held on `dir` for `seconds`.
func _walk(sim, me, dir: Vector2, seconds: float) -> void:
	for i in int(seconds * 30.0):
		sim.avatar.set_input(dir, me.input_aim, false)
		sim.update(DT)
	sim.avatar.set_input(Vector2.ZERO, me.input_aim, false)
	sim.update(DT)


func test_the_ground_in_the_passage_cannot_step_up_onto_the_catwalk_and_the_deck_cannot_step_down_into_the_passage() -> void:
	var g := _game()
	var sim = g.sim
	var me = g.me
	_open_gate(sim)
	# from the street in through the open gateway: on the ground all the way, the bridge's tile included
	_put(me, Vector2(39.5, 14.5))
	var deck_seen := false
	for i in 150:
		sim.avatar.set_input(Vector2(0, 1), me.input_aim, false)
		sim.update(DT)
		if sim.levels.on_deck(me):
			deck_seen = true
	check(not deck_seen, "walking through the gateway is never walking on the deck")
	check(me.y > 21.0, "and out into the yard (y=%f)" % me.y)
	# in the passage: east along the catwalk's row does not climb onto the catwalk
	_put(me, Vector2(39.5, 17.5))
	sim.update(DT)
	_walk(sim, me, Vector2(0, 1), 0.2)
	check(int(floor(me.y)) == 18, "in the bridge's tile (y=%f)" % me.y)
	_walk(sim, me, Vector2(1, 0), 2.0)
	check(me.x < 41.0, "the ground does not step onto the catwalk east of the mouth (x=%f)" % me.x)
	check(not sim.levels.on_deck(me), "and is not on the deck there")
	_walk(sim, me, Vector2(-1, 0), 4.0)
	check(me.x >= 37.0, "nor west of it (x=%f)" % me.x)
	# on the catwalk over the gateway: the way down is a ladder
	_put(me, Vector2(45.5, 18.5))
	sim.update(DT)
	_walk(sim, me, Vector2(-1, 0), 2.4)
	check(me.x < 41.0 and me.x > 37.0, "on the bridge over the passage (x=%f)" % me.x)
	check(sim.levels.on_deck(me), "on the deck")
	_walk(sim, me, Vector2(0, 1), 3.0)
	check(me.y < 19.0 and sim.levels.on_deck(me), "the deck does not step down into the passage (y=%f)" % me.y)
	_walk(sim, me, Vector2(0, -1), 3.0)
	check(me.y >= 18.0 and sim.levels.on_deck(me), "nor up into the wall's rows (y=%f)" % me.y)
	g.world.free()


func test_the_passage_is_the_ground_and_in_the_gateway_the_bridge_is_the_deck_and_is_not() -> void:
	var g := _game()
	var sim = g.sim
	var me = g.me
	_open_gate(sim)
	_put(me, Vector2(39.5, 17.5))
	sim.update(DT)
	_walk(sim, me, Vector2(0, 1), 0.2)
	check(int(floor(me.y)) == 18, "in the bridge's tile of the passage")
	check(not sim.levels.on_deck(me), "not on the deck: the scratch rules and the tutorial's climb are the deck's")
	check(sim.gate.who_blocks().has("Ruth"), "in the gateway: the leaves would not close on her")
	_put(me, Vector2(37.5, 24.5))
	# the keeper's post is on the bridge, over the gateway: coming along the catwalk, Dez is above it
	var dez = g.dez
	_put(dez, Vector2(35.5, 18.5))
	sim.update(DT)
	for k in 30:
		dez.x += 0.1
		sim.update(DT)
	check(floor(dez.x) >= 37.0 and int(floor(dez.y)) == 18, "Dez is over the passage (%f,%f)" % [dez.x, dez.y])
	check(sim.levels.on_deck(dez), "on the deck")
	check(not sim.gate.who_blocks().has("Dez"), "and not in the gateway")
	sim.gate.request(false, "player")
	for i in 90:
		sim.update(DT)
	eq(sim.gate.open, 0.0, "the gate shuts under the one on the bridge")
	g.world.free()


func test_the_towers_are_shut_at_the_street_and_the_outside_ground_for_the_avatar_and_open_for_the_old_yard() -> void:
	var g := _game()
	var sim = g.sim
	var me = g.me
	# on the west tower, walking north (the street) and west (the ground outside): the deck's edge stops them
	_put(me, Vector2(18.5, 16.5))
	sim.update(DT)
	_walk(sim, me, Vector2(0, -1), 2.0)
	check(me.y >= 15.0, "no step north off the tower (y=%f)" % me.y)
	_walk(sim, me, Vector2(-1, 0), 2.0)
	check(me.x >= 17.0, "none west off it (x=%f)" % me.x)
	# from the street, walking south onto it
	_put(me, Vector2(18.5, 11.5))
	sim.update(DT)
	_walk(sim, me, Vector2(0, 1), 3.0)
	check(me.y < 15.0, "no step onto the tower from the street (y=%f)" % me.y)
	check(not sim.world.on_deck(me.x, me.y), "and the avatar is on the ground")
	# the east tower, from the east
	_put(me, Vector2(70.5, 16.5))
	sim.update(DT)
	_walk(sim, me, Vector2(-1, 0), 3.0)
	check(me.x > 66.9, "no step onto the east tower from the ground outside (x=%f)" % me.x)
	g.world.free()
	# the old yard (no avatar) is as it was: the ground beside the tower is open
	var old := Helpers.make(1, 1)
	var w = old.world
	old.sim.update(DT)
	check(w.solid_p[14 * w.W + 18] == 0 and w.solid_p[16 * w.W + 16] == 0 and w.solid_z[14 * w.W + 18] == 0, "with no avatar the tiles beside the tower are open, as ever")
	check(w.solid_z[18 * w.W + 36] == 0, "and so is the catwalk beside the gate for the dead")
	eq(old.sim.levels.on_deck(old.sim.people[0]), w.on_deck(old.sim.people[0].x, old.sim.people[0].y), "and on_deck is the world's")
	w.free()


func test_a_post_on_a_deck_is_not_to_be_taken_from_the_ground_below_it_nor_the_gate_lever_from_the_deck() -> void:
	var g := _game()
	var sim = g.sim
	var me = g.me
	_open_gate(sim)
	# in the open gateway, a step from the gate post's spot on the bridge: on the ground, so the post is not within reach at all
	_put(me, Vector2(39.5, 19.6))
	sim.update(DT)
	var kinds: Array = []
	for c in sim.interact.candidates():
		kinds.append("%s:%s" % [c.kind, c.id])
	check(not kinds.has("post:gate"), "the gate post is not offered to somebody in the passage below it: %s" % str(kinds))
	var from := Vector2(me.x, me.y)
	var r: Dictionary = sim.interact.take_post("gate")
	check(not bool(r.ok), "and cannot be taken: %s" % str(r.why))
	check(Vector2(me.x, me.y).distance_to(from) < 0.001, "the avatar's feet were not put up on the bridge")
	# on the bridge itself it is (come onto it along the catwalk)
	_put(me, Vector2(36.5, 18.5))
	sim.update(DT)
	_put(me, Vector2(38.5, 18.5))
	sim.update(DT)
	check(sim.levels.on_deck(me), "on the deck")
	kinds = []
	for c in sim.interact.candidates():
		kinds.append("%s:%s" % [c.kind, c.id])
	check(kinds.has("post:gate"), "the gate post is offered on the bridge: %s" % str(kinds))
	var gc: Dictionary = sim.interact.gate_candidate()
	check(not gc.is_empty() and not bool(gc.ok) and String(gc.why) == "Climb down first", "the lever is on the ground: from the deck it says so (%s)" % str(gc))
	var used: Dictionary = sim.interact.use(gc)
	check(not bool(used.ok), "and E at it does nothing")
	r = sim.interact.take_post("gate")
	check(bool(r.ok), "the post is taken from the deck: %s" % str(r.why))
	g.world.free()


func test_somebody_on_the_bridge_goes_down_by_a_ladder_not_through_the_open_gateway() -> void:
	var g := _game()
	var sim = g.sim
	var dez = g.dez
	_open_gate(sim)
	_put(dez, Vector2(38.5, 18.5))
	sim.update(DT)
	check(sim.levels.on_deck(dez), "Dez is on the bridge")
	dez.drafted = true
	check(sim.order_move(dez, 39.5, 25.5), "ordered to the yard below the gate")
	var through := false
	var arrived := false
	for i in 1500:
		sim.update(DT)
		if [37, 38, 39, 40].has(floori(dez.x)) and [19, 20].has(floori(dez.y)):
			through = true
		if Vector2(dez.x, dez.y).distance_to(Vector2(39.5, 25.5)) < 1.0:
			arrived = true
			break
	check(not through, "he does not step down off the bridge into the open passage")
	check(arrived, "he gets there, by a ladder (%f,%f)" % [dez.x, dez.y])
	g.world.free()
