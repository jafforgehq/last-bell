extends "res://tests/case.gd"
## The foundation of the One House town (WP1): the generator's data, the dormant dead, the houses registry through the real colony loop, a walk down the street, and the real
## game booting on a town. Lean on purpose: one mini town (64 x 64, 4 blocks) per test, about a second each.

const Helpers := preload("res://tests/helpers.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")


func test_the_town_is_the_same_for_a_seed_and_its_start_house_and_rescue_spots_are_made_for_the_game() -> void:
	var t := TownGen.make(1, {"blocks": 2})
	eq(TownGen.digest(TownGen.make(1, {"blocks": 2})), TownGen.digest(t), "the same seed, the same town")
	check(TownGen.digest(TownGen.make(2, {"blocks": 2})) != TownGen.digest(t), "another seed, another town")
	eq(t.size, Vector2i(64, 64), "two blocks a side")
	var start: Dictionary = t.houses[int(t.start.house)]
	check(not bool(start.fenced), "the start house's lot is not fenced")
	eq(int(t.start.ring.free), int(t.start.ring.total), "its border and the row inside it are free: no tree, no prop, no mark")
	var inside := 0
	for r in t.dead:
		if int(r.house) == int(t.start.house) and int(r.room) >= 0:
			inside += 1
	eq(inside, 3, "three dead stand in the start house")
	eq(t.rescue.size(), 2, "two rescue spots in the small town")
	for r in t.rescue:
		var h: Dictionary = t.houses[int(r.house)]
		check(h.dead.size() >= 2 and h.dead.size() <= 4, "a guard of two to four in rescue house %d: %d" % [int(r.house), h.dead.size()])
		var in_room := 0
		for i in h.dead:
			if int(t.dead[i].room) == int(r.room):
				in_room += 1
		eq(in_room, 1, "one of them in the survivor's room")
		check(String(h.address) != "", "the house has an address")
	for h in t.houses:
		check(h.rooms.size() >= 2, "house %d has rooms" % int(h.id))
		var exterior := 0
		for d in h.doors:
			if bool(d.exterior):
				exterior += 1
			for tile in d.tiles:
				eq(int(t.data.solidZ[tile.y * 64 + tile.x]), 0, "a doorway is open")
		check(exterior >= 1, "house %d has a door to the street" % int(h.id))
	for r in t.dead:
		if int(r.room) >= 0:
			eq(TownGen.room_at(t, r.pos.x, r.pos.y), int(r.room), "a dead one's room is the room it stands in")


func test_the_dead_wake_near_the_avatar_never_above_the_cap_sleep_far_away_and_a_killed_one_stays_killed() -> void:
	var g := Helpers.town_game(1)
	var sim = g.sim
	var field = sim.field
	field.active_cap = 12
	eq(field.counts().dormant, g.town.dead.size(), "every one dormant at the start")
	for i in 60:
		sim.update(1.0 / 30.0)
		check(sim.zombies.size() <= 12, "never above the cap: %d" % sim.zombies.size())
	var awake: int = field.counts().active
	check(awake >= 3 and awake <= 12, "those near wake: %d" % awake)
	for z in sim.zombies:
		check(field.rec_of.has(z), "each one awake is a Sim.Zombie the field knows")
	# one is shot dead, then the avatar is carried off far away
	var victim = sim.zombies[0]
	sim._hurt_zombie(victim, 1000.0, 0.0, sim.avatar.player())
	sim.update(1.0 / 30.0)
	for i in 10:
		sim.update(1.0 / 30.0)
	eq(field.counts().killed, 1, "the killed one is closed for good")
	var me = sim.avatar.player()
	me.x = 60.0
	me.y = 4.0
	for z in sim.zombies:
		if z.state == "chase":
			z.state = "wander"
	for i in 30:
		sim.update(1.0 / 30.0)
	check(field.slept_total > 0, "those left behind went back to sleep")
	eq(field.counts().killed, 1, "the killed one never wakes")
	# the save is compact and comes back the same
	sim.pre_save()
	var saved: Dictionary = field.save()
	eq(int(saved.n), g.town.dead.size(), "every record is in the save")
	check(JSON.stringify(saved).length() < 20 * g.town.dead.size() + 100, "about 12 bytes a record: %d bytes" % JSON.stringify(saved).length())
	var before: Dictionary = field.counts()
	field.load_state(JSON.parse_string(JSON.stringify(saved)))
	eq(field.counts().killed, before.killed, "the killed come back killed")
	eq(field.counts().dormant, before.dormant + before.active, "the rest come back dormant")
	g.world.free()


func test_the_three_dead_of_the_start_house_are_cleared_through_the_real_loop() -> void:
	var g := Helpers.town_game(1)
	var sim = g.sim
	var house: int = sim.houses.start_house()
	eq(sim.houses.dead_in_house(house), 3, "three to clear")
	for i in 20:
		sim.update(1.0 / 30.0)
	var shot := 0
	for z in sim.zombies.duplicate():
		if sim.houses.house_at(z.x, z.y) == house:
			sim._hurt_zombie(z, 1000.0, 0.0, sim.avatar.player())
			shot += 1
	eq(shot, 3, "all three had woken and stood inside")
	for i in 20:
		sim.update(1.0 / 30.0)
	eq(sim.houses.dead_in_house(house), 0, "no dead left in the start house")
	for r in sim.houses.rooms_of(house):
		eq(sim.houses.dead_in_room(r), 0, "nor in any of its rooms")
	eq(sim.kills, 3, "and they were counted")
	g.world.free()


func test_the_avatar_walks_out_of_the_door_and_down_the_street_in_the_colonys_loop_cheaply_and_without_an_error() -> void:
	var g := Helpers.town_game(1)
	var sim = g.sim
	var me = sim.avatar.player()
	var door: Dictionary = {}
	for d in sim.houses.doors_of(sim.houses.start_house()):
		if bool(d.exterior):
			door = d
	var out: Vector2i = door.out
	var path: Array = sim.path_p.find(sim.world.solid_p, me.x, me.y, float(out.x) + 0.5, float(out.y) + 0.5)
	check(not path.is_empty(), "a way to the door")
	# then along the street (the nearest road tile south or north of the door: the roads of a block are 28 to 31 of every 32)
	var street := Vector2(float(out.x) + 0.5, float(int(out.y / 32) * 32 + 29) + 0.5)
	path.append_array(sim.path_p.find(sim.world.solid_p, float(out.x) + 0.5, float(out.y) + 0.5, street.x, street.y))
	var i := 0
	var total_us := 0
	for step in 600:
		me.hp = 100.0
		var move := Vector2.ZERO
		if i < path.size():
			var wp: Vector2 = path[i]
			move = wp - Vector2(me.x, me.y)
			if move.length() < 0.5:
				i += 1
		sim.avatar.set_input(move, Vector2(me.x, me.y + 4.0), false)
		var t := Time.get_ticks_usec()
		sim.update(1.0 / 30.0)
		total_us += Time.get_ticks_usec() - t
		sim.events.clear()
	check(sim.zombies.size() <= sim.field.active_cap, "never above the cap")
	check(float(total_us) / 600000.0 < 4.0, "a step under 4 ms on average: %.2f ms" % (float(total_us) / 600000.0))
	check(sim.houses.house_at(me.x, me.y) != sim.houses.start_house(), "she is out of the house")
	g.world.free()


func test_main_boots_a_town_run_with_the_towns_rules_and_none_of_the_schools_views() -> void:
	var win: Window = Engine.get_main_loop().root
	var saved := {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	Engine.set_meta("run", {"difficulty": 1, "seed": 7, "town": true, "avatar": true, "town_opts": {"blocks": 2}})
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	check(main.sim.has_method("pre_save") and main.sim.get("houses") != null, "the rules are the town's (TownSim)")
	check(main.town != null, "the facade is there")
	eq(main.sim.player_id, "ruth", "Ruth is the player")
	check(main.world.has_method("show_chunks"), "the world is the chunked one")
	eq(main.world.W, 64, "of the mini town")
	check(main.dressing_view == null and main.parking_view == null and main.gate_node == null, "no dressing, parking or gate node of the school")
	check(not main.life_view.enabled, "the base's little life is off")
	main._process(1.0 / 60.0)
	main.queue_free()
	await Engine.get_main_loop().process_frame
	win.content_scale_mode = saved.mode
	win.content_scale_aspect = saved.aspect
	win.content_scale_size = saved.scale_size
	win.size = saved.size
	win.position = saved.position
