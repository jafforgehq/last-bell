extends "res://tests/case.gd"
## A played trip (round 14, scripts/raid/raid_run.gd): the squad in a small site of our own (a street, a house with a
## door and two containers, dead standing about), orders, searching, noise, bites, helping, retreating, and the
## result in the trip's format. The real sites are made by site_gen.gd (tests/test_site_gen.gd).

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const Helpers := preload("res://tests/helpers.gd")

const W := 30
const H := 16


## A site 30 x 16: open ground, a house (x 14 to 24, y 3 to 12) with a wall all round except a door at (14, 8),
## two containers inside, the entry on the left, the exit round it.
func _site(dead: Array = []) -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	data["objects"] = []
	data["walls"] = []
	data["marks"] = []
	data["lights"] = []
	data["trees"] = []
	data["segments"] = []
	data["people"] = []
	data["spawns"] = []
	return {
		"name": "A test house", "kind": "houses", "danger": 2, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(-1, -1),
		"containers": [
			{"id": "c1", "pos": Vector2(16.5, 6.5), "at": Vector2(16.5, 5.5), "kind": "cabinet", "loot": {"food": 10, "meds": 4}, "search_s": 4.0, "room": "hall"},
			{"id": "c2", "pos": Vector2(21.5, 9.5), "at": Vector2(21.5, 10.5), "kind": "shelf", "loot": {"scrap": 25, "ammo": 60}, "search_s": 6.0, "room": "back"},
		],
		"dead": dead, "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


func _run(dead: Array = [], size: int = 2, vehicle: String = "", survivor: bool = false) -> Dictionary:
	var site := _site(dead)
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var g := Helpers.make(3, 1, 6)
	var members: Array = []
	for i in size:
		var p = g.sim.people[i]
		members.append({"def": p.def, "hp": 100.0, "skills": p.skills})
	var run = RaidRun.new(site, world, FxNull.new(), members, 300.0, vehicle, 1.0, survivor)
	return {"run": run, "world": world, "g": g}


func _free(ctx: Dictionary) -> void:
	ctx.world.free()
	ctx.g.world.free()


func _step(run, seconds: float) -> void:
	for i in int(seconds * 30.0):
		run.update(1.0 / 30.0)


func test_the_squad_arrives_at_the_entry_with_their_own_skills_and_guns() -> void:
	var ctx := _run([], 3)
	var run = ctx.run
	eq(run.squad.size(), 3, "three people")
	for p in run.squad:
		check(Vector2(p.x, p.y).distance_to(Vector2(3.5, 8.5)) < 2.5, "%s is at the entry" % p.first)
		check(p.drafted, "%s fights" % p.first)
		check(p.weapon != "", "with their own gun")
	eq(run.phase, "play", "playing")
	eq(run.containers.size(), 2, "two containers")
	_free(ctx)


func test_a_person_walks_where_ordered_and_searches_a_container_by_standing_at_it() -> void:
	var ctx := _run([], 1)
	var run = ctx.run
	var dez = run.squad[0]
	check(run.order_search(dez, "c1"), "ordered to search the cabinet")
	_step(run, 3.0)
	check(not run.container("c1").looted, "not done in three seconds (it walks first)")
	_step(run, 15.0)
	check(run.container("c1").looted, "done")
	eq(int(run.carried.get("food", 0)), 10, "ten food in the bags")
	eq(int(run.carried.get("meds", 0)), 4, "and four meds")
	check(run.log.size() >= 1 and String(run.log[0]).contains("cabinet"), "the log says so: %s" % str(run.log))
	_free(ctx)


func test_the_bags_hold_only_so_much_and_the_rest_stays_in_the_container() -> void:
	var ctx := _run([], 1)
	var run = ctx.run
	eq(run.capacity(), RaidRun.CARRY, "one person carries thirty")
	run.container("c2").loot = {"scrap": 25, "ammo": 60}
	check(run.order_search(run.squad[0], "c2"), "searching the shelf")
	_step(run, 25.0)
	eq(run.carried_total(), RaidRun.CARRY, "the bags are full")
	check(not run.container("c2").looted, "the shelf still has something")
	check(int(run.container("c2").loot.get("ammo", 0)) > 0 or int(run.container("c2").loot.get("scrap", 0)) > 0, "what did not fit stays: %s" % str(run.container("c2").loot))
	_free(ctx)


func test_a_vehicle_gives_the_bags_more_room() -> void:
	var ctx := _run([], 1, "van")
	eq(ctx.run.capacity(), RaidRun.CARRY + roundi(float(RaidRun.VEHICLE_CARRY) * 1.5), "the van's room is added, by its cargo")
	_free(ctx)


func test_the_dead_stand_until_they_notice_and_then_hunt() -> void:
	var ctx := _run([{"pos": Vector2(20.5, 7.5), "kind": "walker", "state": "still"}, {"pos": Vector2(27.5, 14.5), "kind": "walker", "state": "still"}])
	var run = ctx.run
	_step(run, 4.0)
	var inside = run.sim.zombies[0]
	var far = run.sim.zombies[1]
	check(run._sleeping.has(inside) or inside.state == "hunt" or inside.state == "dying", "the one inside the house has not seen anyone through the wall")
	run.order_move(run.squad[0], Vector2(15.5, 8.5))
	_step(run, 8.0)
	check(inside.state == "hunt" or inside.state == "dying" or inside.state == "dead", "once the squad is in the house the one inside hunts or is shot: %s" % inside.state)
	check(run._sleeping.has(far), "and the far one still sleeps")
	_free(ctx)


func test_a_shot_wakes_the_dead_within_earshot_only() -> void:
	var ctx := _run([{"pos": Vector2(10.5, 3.5), "kind": "walker", "state": "still"}, {"pos": Vector2(28.5, 14.5), "kind": "walker", "state": "still"}])
	var run = ctx.run
	run._noise(Vector2(4.5, 5.5))
	var near_z = run.sim.zombies[0]
	var far_z = run.sim.zombies[1]
	eq(near_z.state, "hunt", "the near one hunts")
	check(run._sleeping.has(far_z) or far_z.state == "wander", "the far one did not hear")
	_free(ctx)


func test_a_bite_hurts_and_a_person_who_is_down_is_lost_unless_a_friend_gets_them_up() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	var a = run.squad[0]
	var b = run.squad[1]
	run._bitten[String(a.id)] = true
	var r: Dictionary = run.result()
	eq(r.hurt.get(String(a.id), ""), "bite", "a bitten person is hurt")
	check(r.lost.is_empty(), "and nobody is lost")
	a.downed = true
	r = run.result()
	check(r.lost.has(String(a.id)), "a person left down is lost")
	b.x = a.x + 0.6
	b.y = a.y
	check(run.order_help(b, a), "the other goes to help")
	_step(run, RaidRun.HELP_S + 2.0)
	check(not a.downed, "and gets them up")
	near(a.hp, RaidRun.GET_UP_HP, 0.001, "on a little health")
	r = run.result()
	check(not r.lost.has(String(a.id)), "who is not lost")
	_free(ctx)


func test_retreating_ends_the_run_when_everyone_is_at_the_exit() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	run.order_move(run.squad[0], Vector2(10.5, 3.5))
	_step(run, 5.0)
	run.retreat()
	eq(run.phase, "retreat", "retreating")
	_step(run, 20.0)
	check(run.finished(), "everyone is out: the run is over")
	_free(ctx)


func test_the_result_is_in_the_trips_format_with_ammo_used_and_a_cleared_place() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	run.order_search(run.squad[0], "c1")
	_step(run, 20.0)
	run.retreat()
	_step(run, 20.0)
	var r: Dictionary = run.result()
	for k in ["loot", "hurt", "lost", "ammo_used", "beats"]:
		check(r.has(k), "the result has %s" % k)
	eq(int(r.loot.get("food", 0)), 10, "the loot is what was searched")
	check(r.get("clear", false), "a place with no dead left is cleared")
	check(not r.get("rescue", false), "nobody was rescued: nobody was there")
	_free(ctx)


func test_a_survivor_is_rescued_when_the_far_spot_is_searched() -> void:
	var ctx := _run([], 1, "", true)
	var run = ctx.run
	check(run.container("survivor").size() > 0, "there is a place to find them")
	run.order_search(run.squad[0], "survivor")
	_step(run, 25.0)
	check(bool(run.container("survivor").looted), "found")
	check(run.result().get("rescue", false), "rescued")
	_free(ctx)


func test_everyone_down_ends_the_run_with_nothing_brought_home() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	run.carried = {"food": 12}
	for p in run.squad:
		p.downed = true
	run.update(1.0 / 30.0)
	check(run.finished(), "nobody can go on")
	var r: Dictionary = run.result()
	eq(r.lost.size(), 2, "both are lost")
	check(r.loot.is_empty(), "and nothing comes home")
	_free(ctx)


func test_a_squad_left_alone_stays_where_it_stands() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	var before: Array = []
	for p in run.squad:
		before.append(Vector2(p.x, p.y))
	_step(run, 6.0)
	for i in run.squad.size():
		check(Vector2(run.squad[i].x, run.squad[i].y).distance_to(before[i]) < 0.3, "%s did not wander off" % run.squad[i].first)
	_free(ctx)


func test_what_a_person_is_doing_can_be_asked() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	run.order_search(run.squad[0], "c1")
	eq(run.searching_of(run.squad[0]), "c1", "searching the cabinet")
	eq(run.searching_of(run.squad[1]), "", "the other is not")
	run.squad[1].downed = false
	run.squad[0].downed = true
	run._searching.clear()
	check(run.order_help(run.squad[1], run.squad[0]), "helping")
	check(run.helping_of(run.squad[1]) == run.squad[0], "and who they help can be asked")
	_free(ctx)


# ---------------------------------------------------------------- review fixes --

func test_the_survivor_stands_beside_the_place_not_in_it_and_can_be_picked() -> void:
	var ctx := _run([], 1, "", true)
	var run = ctx.run
	var c: Dictionary = run.container("survivor")
	check(not c.is_empty(), "there is someone to find")
	for o in run.containers:
		if String(o.id) != "survivor":
			check(Vector2(o.pos).distance_to(Vector2(c.pos)) >= 0.9, "not on %s's spot" % o.id)
	check(not run.sim.world.is_solid(run.sim.world.solid_p, c.pos.x, c.pos.y), "on open ground")
	_free(ctx)


func test_dead_shot_in_their_sleep_fall_and_go_like_the_others() -> void:
	var ctx := _run([{"pos": Vector2(8.5, 8.5), "kind": "walker", "state": "still"}], 1)
	var run = ctx.run
	var z = run.sim.zombies[0]
	check(run._sleeping.has(z), "asleep")
	run.sim._hurt_zombie(z, 1000.0, 0.0, run.squad[0])
	_step(run, 4.0)
	check(not run._sleeping.has(z) and (z.state == "dead" or z.remove or not run.sim.zombies.has(z)), "it has fallen: %s" % z.state)
	_free(ctx)


func test_a_bite_is_the_bitten_ones_alone_even_when_two_stand_on_one_spot() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	var a = run.squad[0]
	var b = run.squad[1]
	b.x = a.x
	b.y = a.y
	run.sim.events.append({"type": "bite", "x": a.x, "y": a.y, "who": String(a.id)})
	run.update(1.0 / 30.0)
	var r: Dictionary = run.result()
	check(r.hurt.has(String(a.id)) and not r.hurt.has(String(b.id)), "only the one who was bitten is hurt: %s" % str(r.hurt))
	_free(ctx)


func test_a_person_got_up_fights_on_and_a_refused_move_keeps_the_search() -> void:
	var ctx := _run([], 2)
	var run = ctx.run
	var a = run.squad[0]
	var b = run.squad[1]
	run.order_search(a, "c1")
	check(not run.order_move(a, Vector2(14.5, 3.5)), "a wall tile is refused")
	eq(run.searching_of(a), "c1", "and the search goes on")
	a.downed = true
	b.x = a.x + 0.6
	b.y = a.y
	run.order_help(b, a)
	_step(run, RaidRun.HELP_S + 2.0)
	check(not a.downed and a.drafted, "got up and fighting")
	_free(ctx)


func test_the_squad_shoots_only_what_it_can_see() -> void:
	var ctx := _run([{"pos": Vector2(16.5, 6.5), "kind": "walker", "state": "still"}], 1)
	var run = ctx.run
	var p = run.squad[0]
	p.x = 11.5
	p.y = 6.5
	check(run.sim._find_target(p) == null, "a sleeper behind the house's wall is not a target")
	p.x = 16.5
	p.y = 10.5
	check(run.sim._find_target(p) != null, "inside, in sight: it is")
	_free(ctx)


func test_a_place_with_no_danger_can_be_cleared_too() -> void:
	var ctx := _run([], 1)
	ctx.run.site["danger"] = 0
	check(ctx.run.result().get("clear", false), "no dead left: cleared, whatever the danger")
	_free(ctx)
