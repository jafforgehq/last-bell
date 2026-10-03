extends "res://tests/case.gd"
## The avatar and the squad in a played place (round 17, slice 1, S1.6a: scripts/raid/raid_run.gd, raid_sim.gd and
## scripts/raid/squad_ai.gd). The player's one survivor walks, aims and shoots in a site with walls; searches by standing at a
## container; the people who came follow them (the default), hold, cover, search and go back, and stop to fire at what they
## see; a request goes through the radio's willingness; the next of the squad leads when the avatar falls; the result carries
## the health, skills and trust for the base. The views are not here: they feed `sim.avatar.set_input` and read the people.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const Helpers := preload("res://tests/helpers.gd")

const W := 30
const H := 16
const DT := 1.0 / 30.0


## A site 30 x 16 (as test_raid_run's): open ground, a house (x 14 to 24, y 3 to 12) with a wall all round except a door at
## (14, 8), two containers inside, the entry on the left, the exit round it.
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


## A run of `size` people (Ruth, Dez, Ana...) in the site. With `avatar` the first of them (Ruth) is the player, with a rifle.
func _run(dead: Array = [], size: int = 3, avatar: bool = true) -> Dictionary:
	var site := _site(dead)
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var g := Helpers.make(3, 1, 6)
	var members: Array = RaidRun.squad_of(g.sim.people.slice(0, size))
	var run = RaidRun.new(site, world, FxNull.new(), members, 300.0)
	var out := {"run": run, "world": world, "g": g}
	if avatar:
		var me = run.squad[0]
		me.weapon = "rifle"
		me.gun = run.sim.weapons["rifle"]
		me.mag = int(me.gun.mag)
		check(run.set_player(me), "the first of them is the player")
		out["me"] = me
	return out


func _free(ctx: Dictionary) -> void:
	ctx.world.free()
	ctx.g.world.free()


func _step(run, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		run.update(DT)


func _at(p, x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.path = []
	p.goal_key = ""
	p.moving = false


func _pos(p) -> Vector2:
	return Vector2(p.x, p.y)


func _count(run, type: String) -> int:
	var n := 0
	for e in run.events:
		if String(e.get("type", "")) == type:
			n += 1
	return n


## One of the dead standing where it is, with a lot of health, not moving (it is a target, nothing more).
func _post_dead(run, x: float, y: float, hp: float = 1000.0):
	var z = run.sim.spawn(x, y, "wander", "walker")
	z.hp = hp
	z.stagger = 1.0e6
	z.limp = false
	return z


# ------------------------------------------------------------- the avatar here --

func test_the_player_is_the_leader_and_nobody_orders_them() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	check(run.avatar() == me, "avatar() is the player")
	check(me.player and run.sim.player_id == String(me.id), "the sim knows who")
	check(not run.order_move(me, Vector2(8.5, 8.5)), "the avatar is not ordered about")
	check(not run.order_search(me, "c1"), "nor ordered to search")
	var other = run.squad[1]
	check(run.set_player(other) and run.avatar() == other, "any member of the squad can lead")
	check(run.leader() == other and not me.player, "the leader is the one and only")
	check(run.set_player(null) and run.avatar() == null, "set_player(null) gives the avatar up")
	_free(ctx)


func test_the_avatar_walks_in_a_site_and_a_wall_stops_them() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 3.5, 5.5)
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(20.5, 5.5), false)
	_step(run, 1.0)
	near(me.x, 3.5 + 3.2, 0.05, "three point two tiles in a second")
	_step(run, 5.0)
	near(me.x, 14.0 - 0.3, 0.02, "against the house's wall, a radius short of it")
	check(not me.moving, "not walking on the spot")
	# through the door at (14, 8)
	_at(me, 12.5, 8.5)
	_step(run, 1.0)
	check(me.x > 15.0, "through the door: %f" % me.x)
	_free(ctx)


func test_the_runs_input_wrappers_reach_the_avatar_and_let_go_when_the_trip_is_over() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 3.5, 5.5)
	run.set_input(Vector2(1, 0), Vector2(9.5, 5.5), true)
	eq(me.input_move, Vector2(1, 0), "the move")
	eq(me.input_aim, Vector2(9.5, 5.5), "the aim")
	check(me.input_fire, "the trigger")
	me.mag = 3
	check(run.reload(), "the reload key is taken")
	check(me.input_reload, "and passed on")
	check(run.melee(), "so is the melee key")
	run.phase = "ended"
	run.set_input(Vector2(1, 0), Vector2(9.5, 5.5), true)
	eq(me.input_move, Vector2.ZERO, "the hands are let go once it is over")
	check(not me.input_fire and not run.reload() and not run.melee(), "and nothing is fired, reloaded or swung")
	_free(ctx)


func test_the_avatar_fires_what_they_aim_at_and_it_costs_ammunition_and_wakes_the_dead() -> void:
	var ctx := _run([{"pos": Vector2(9.5, 3.5), "kind": "walker", "state": "still"}, {"pos": Vector2(28.5, 14.5), "kind": "walker", "state": "still"}])
	var run = ctx.run
	var me = ctx.me
	_at(me, 5.5, 3.5)
	var near_z = run.sim.zombies[0]
	var far_z = run.sim.zombies[1]
	var ammo0: float = run.sim.stock.ammo
	near_z.hp = 2.0
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(9.5, 3.5), true)
	_step(run, 2.5)
	check(near_z.state == "dying" or near_z.state == "dead", "the one they aimed at is down: %s" % near_z.state)
	check(run.sim.stock.ammo < ammo0, "and the shots cost ammunition")
	check(run._sleeping.has(far_z) or far_z.state == "wander", "the far one did not hear it")
	check(me.stats.shots > 0, "counted")
	_free(ctx)


# ------------------------------------------------------------ searching by hand --

func test_the_avatar_searches_a_container_by_standing_at_it() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 8.5, 6.5)
	check(not run.begin_search(me, "c1"), "too far from the cabinet to begin")
	_at(me, 16.5, 6.5)
	check(run.begin_search(me, "c1"), "at it: begins")
	eq(run.searching_of(me), "c1", "searching the cabinet")
	_step(run, 3.0)
	check(not run.container("c1").looted, "not done in three seconds")
	check(float(run.container("c1").progress) > 2.0, "but it goes on: %f" % float(run.container("c1").progress))
	_step(run, 2.0)
	check(run.container("c1").looted, "done")
	eq(int(run.carried.get("food", 0)), 10, "ten food in the bags")
	eq(run.searching_of(me), "", "and they are not searching any more")
	check(run.log.size() >= 1 and String(run.log[0]).contains("cabinet"), "the log says so: %s" % str(run.log))
	_free(ctx)


func test_walking_away_or_firing_cancels_the_avatars_search_and_keeps_what_was_done() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 16.5, 6.5)
	run.begin_search(me, "c1")
	_step(run, 2.0)
	run.sim.avatar.set_input(Vector2(0, 1), Vector2.ZERO, false)
	_step(run, 0.2)
	eq(run.searching_of(me), "", "walking away cancels it")
	var done: float = float(run.container("c1").progress)
	check(done > 1.5 and done < 4.0, "what was done is kept: %f" % done)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2.ZERO, false)
	_at(me, 16.5, 6.5)
	check(run.begin_search(me, "c1"), "they can begin again")
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(20.5, 6.5), true)
	_step(run, 0.2)
	eq(run.searching_of(me), "", "firing cancels it")
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(20.5, 6.5), false)
	_at(me, 16.5, 6.5)
	run.begin_search(me, "c1")
	run.stop_search(me)
	eq(run.searching_of(me), "", "stop_search ends it")
	_free(ctx)


func test_the_scene_can_ask_what_is_near_and_what_is_under_the_mouse() -> void:
	var ctx := _run()
	var run = ctx.run
	var near_c: Array = run.containers_near(Vector2(16.0, 6.0), 1.5)
	eq(near_c.size(), 1, "one container within a tile and a half")
	eq(String(near_c[0].id), "c1", "the cabinet")
	eq(run.containers_near(Vector2(5.0, 5.0), 3.0).size(), 0, "none out in the road")
	eq(run.containers_near(Vector2(19.0, 8.0), 20.0).size(), 2, "both in a wide ring")
	var order: Array = run.containers_near(Vector2(20.0, 9.0), 20.0)
	eq(String(order[0].id), "c2", "the nearest first")
	eq(String(run.container_at(Vector2(16.5, 5.5)).get("id", "")), "c1", "the middle of the cabinet's furniture")
	eq(String(run.container_at(Vector2(16.5, 6.5)).get("id", "")), "c1", "and the spot you stand at")
	check(run.container_at(Vector2(8.5, 8.5)).is_empty(), "nothing in the open")
	run.container("c1")["looted"] = true
	eq(run.containers_near(Vector2(16.0, 6.0), 1.5).size(), 0, "a searched one is no longer offered")
	eq(String(run.container_at(Vector2(16.5, 5.5)).get("id", "")), "c1", "but the point still names it (the radio says it is done)")
	_free(ctx)


func test_a_downed_friend_is_got_up_by_the_avatar_standing_beside_them() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var dez = run.squad[1]
	dez.downed = true
	dez.hp = 0.0
	_at(dez, 8.5, 8.5)
	_at(me, 3.5, 3.5)
	check(not run.begin_help(me, dez), "too far to begin")
	_at(me, 9.1, 8.5)
	check(run.begin_help(me, dez), "beside them: begins")
	_step(run, RaidRun.HELP_S + 0.5)
	check(not dez.downed, "got up")
	near(dez.hp, RaidRun.GET_UP_HP, 0.001, "on a little health")
	_free(ctx)


# ----------------------------------------------------------------- follow --

func test_the_squad_follows_the_player_by_default() -> void:
	var ctx := _run()
	var run = ctx.run
	for i in [1, 2]:
		eq(run.squad[i].stance, "follow", "%s follows from the start" % run.squad[i].first)
	eq(run.squad[0].stance, "", "the player has no stance")
	_free(ctx)


func test_followers_stay_still_while_the_player_stays_close() -> void:
	var ctx := _run()
	var run = ctx.run
	var before: Array = [_pos(run.squad[1]), _pos(run.squad[2])]
	_step(run, 5.0)
	check(_pos(run.squad[1]).distance_to(before[0]) < 0.05, "Dez stays where he stands")
	check(_pos(run.squad[2]).distance_to(before[1]) < 0.05, "Ana stays where she stands")
	_free(ctx)


func test_followers_keep_within_reach_of_a_walking_player_and_do_not_jitter() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 3.5, 8.5)
	_at(run.squad[1], 2.4, 8.0)
	_at(run.squad[2], 2.4, 9.0)
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(30.5, 8.5), false)
	var last: Array = [_pos(run.squad[1]), _pos(run.squad[2])]
	var flips := [0, 0]
	var dir_x := [0.0, 0.0]
	var worst := [0.0, 0.0]
	var worst_step := 0.0
	var steps := int(round(3.0 / DT))
	for s in steps:
		run.update(DT)
		for k in 2:
			var p = run.squad[k + 1]
			var v: Vector2 = _pos(p) - last[k]
			last[k] = _pos(p)
			worst_step = maxf(worst_step, v.length())
			if absf(v.x) > 0.002:
				if dir_x[k] != 0.0 and signf(v.x) != dir_x[k]:
					flips[k] += 1
				dir_x[k] = signf(v.x)
			worst[k] = maxf(worst[k], _pos(p).distance_to(_pos(me)))
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(30.5, 8.5), false)
	_step(run, 2.5)
	var settled: Array = [_pos(run.squad[1]), _pos(run.squad[2])]
	_step(run, 2.0)
	for k in 2:
		var p = run.squad[k + 1]
		check(worst[k] < 3.4, "%s never falls far behind while the player walks: %f" % [p.first, worst[k]])
		eq(flips[k], 0, "%s does not turn back and forth" % p.first)
		check(_pos(p).distance_to(settled[k]) < 0.05, "%s has settled once the player stopped" % p.first)
		var d := _pos(p).distance_to(_pos(me))
		check(d <= RaidRun.SquadAI.FOLLOW_R + 0.05 and d >= RaidRun.SquadAI.FOLLOW_MIN - 0.05, "%s stands within reach of the player: %f" % [p.first, d])
		check(p.x < me.x, "%s stands behind the player (they walked east)" % p.first)
	check(worst_step <= 3.7 * DT + 0.002, "nobody moves faster than a hurrying walk: %f" % worst_step)
	check(_pos(run.squad[1]).distance_to(_pos(run.squad[2])) > 0.6, "and the two keep apart")
	_free(ctx)


func test_a_player_who_shuffles_about_does_not_set_the_followers_off() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 8.5, 8.5)
	_at(run.squad[1], 7.0, 8.0)
	_at(run.squad[2], 7.1, 9.0)
	var before: Array = [_pos(run.squad[1]), _pos(run.squad[2])]
	for i in 180:
		var east := (i / 6) % 2 == 0
		run.sim.avatar.set_input(Vector2(1 if east else -1, 0), Vector2(20.5, 8.5), false)
		run.update(DT)
	check(_pos(me).distance_to(Vector2(8.5, 8.5)) < 1.5, "the player stayed about where they were: %s" % str(_pos(me)))
	check(_pos(run.squad[1]).distance_to(before[0]) < 0.4, "Dez did not run about: %f" % _pos(run.squad[1]).distance_to(before[0]))
	check(_pos(run.squad[2]).distance_to(before[1]) < 0.4, "nor did Ana: %f" % _pos(run.squad[2]).distance_to(before[1]))
	_free(ctx)


func test_the_formation_follows_the_way_the_player_walks_not_where_the_mouse_points() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 3.5, 8.5)
	_at(run.squad[1], 2.6, 8.0)
	_at(run.squad[2], 2.6, 9.0)
	# walking east with the mouse up at the top of the map
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(8.5, 0.5), false)
	_step(run, 3.0)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(8.5, 0.5), false)
	_step(run, 3.0)
	for k in [1, 2]:
		var p = run.squad[k]
		check(p.x < me.x - 1.0, "%s is behind them on the road they came by, not under the mouse: %s, player %s" % [p.first, str(_pos(p)), str(_pos(me))])
		check(absf(p.y - me.y) < 1.6, "and not off to the side of the mouse's line: %f" % absf(p.y - me.y))
	_free(ctx)


func test_a_player_who_swings_the_mouse_about_does_not_move_followers_who_are_close_enough() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 8.5, 8.5)
	_at(run.squad[1], 7.2, 8.0)
	_at(run.squad[2], 7.4, 9.2)
	var before: Array = [_pos(run.squad[1]), _pos(run.squad[2])]
	for i in 120:
		var a := float(i) * 0.31
		run.sim.avatar.set_input(Vector2.ZERO, _pos(me) + Vector2.from_angle(a) * 6.0, false)
		run.update(DT)
	check(_pos(run.squad[1]).distance_to(before[0]) < 0.05, "Dez did not move")
	check(_pos(run.squad[2]).distance_to(before[1]) < 0.05, "nor did Ana")
	_free(ctx)


func test_a_follower_in_a_doorway_does_not_stand_in_a_wall_or_cross_it() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 12.5, 8.5)
	_at(run.squad[1], 11.5, 8.5)
	_at(run.squad[2], 10.5, 8.5)
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(30.5, 8.5), false)
	_step(run, 3.0)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(30.5, 8.5), false)
	_step(run, 4.0)
	for k in [1, 2]:
		var p = run.squad[k]
		check(not run.sim.world.is_solid(run.sim.world.solid_p, p.x, p.y), "%s stands on open ground" % p.first)
		check(_pos(p).distance_to(_pos(me)) < 3.2, "%s came through after the player: %f" % [p.first, _pos(p).distance_to(_pos(me))])
	_free(ctx)


# ------------------------------------------------------------------ hold --

func test_hold_sends_a_person_to_the_spot_and_keeps_them_there() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	var r: Dictionary = run.request(dez, "hold", {"at": Vector2(8.5, 5.5)})
	check(r.ok, "Dez agrees: %s" % str(r))
	check(float(r.delay_s) > 0.0, "after a delay")
	eq(dez.stance, "follow", "not yet")
	_step(run, 7.0)
	eq(dez.stance, "hold", "holding")
	check(_pos(dez).distance_to(Vector2(8.5, 5.5)) < 0.2, "at the spot: %s" % str(_pos(dez)))
	_at(ctx.me, 3.5, 8.5)
	run.sim.avatar.set_input(Vector2(0, 1), Vector2(3.5, 20.5), false)
	_step(run, 2.0)
	check(_pos(dez).distance_to(Vector2(8.5, 5.5)) < 0.2, "and the player walking off does not take him")
	_free(ctx)


func test_hold_is_refused_where_they_cannot_walk_and_moved_off_a_wall_where_they_can() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	# a one-tile pocket shut in on every side
	for t in [Vector2i(26, 14), Vector2i(28, 14), Vector2i(27, 13), Vector2i(27, 15)]:
		var i: int = t.y * W + t.x
		run.sim.world.solid_p[i] = 1
		run.sim.world.solid_z[i] = 1
		run.sim.path_p.set_solid(i, true)
	var r: Dictionary = run.request(dez, "hold", {"at": Vector2(27.5, 14.5)})
	check(not r.ok and String(r.why).contains("get there"), "no way in: %s" % str(r))
	r = run.request(dez, "hold", {"at": Vector2(14.5, 5.5)})
	check(r.ok, "a point in a wall is moved to open ground beside it")
	_step(run, 8.0)
	eq(dez.stance, "hold", "holding")
	check(not run.sim.world.is_solid(run.sim.world.solid_p, dez.x, dez.y), "on open ground: %s" % str(_pos(dez)))
	check(_pos(dez).distance_to(Vector2(14.5, 5.5)) < 2.0, "beside the wall they were asked to hold: %s" % str(_pos(dez)))
	_free(ctx)


func test_hold_with_no_spot_holds_where_the_player_stands() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	_at(ctx.me, 9.5, 9.5)
	var r: Dictionary = run.request(dez, "hold")
	check(r.ok, "agreed")
	_step(run, 8.0)
	eq(dez.stance, "hold", "holding")
	check(_pos(dez).distance_to(Vector2(9.5, 9.5)) < 0.3, "where the player stood when they asked: %s" % str(_pos(dez)))
	_free(ctx)


# ----------------------------------------------------------------- cover --

func test_cover_stands_four_or_five_tiles_behind_the_players_aim() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var ana = run.squad[2]
	_at(me, 9.5, 8.5)
	_at(ana, 8.5, 9.0)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(14.5, 8.5), false)
	check(run.request(ana, "cover").ok, "Ana covers")
	_step(run, 9.0)
	eq(ana.stance, "cover", "covering")
	var d := _pos(ana).distance_to(_pos(me))
	check(d >= 3.2 and d <= 5.8, "four or five tiles from the player: %f" % d)
	check(ana.x < me.x - 2.5, "behind them (they aim east): %s" % str(_pos(ana)))
	# the player turns round and aims the other way: she moves to the other side, but not at a flick
	var before := _pos(ana)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(9.5, 14.5), false)
	_step(run, 0.3)
	check(_pos(ana).distance_to(before) < 0.6, "a flick of the mouse does not send her running")
	_step(run, 8.0)
	check(ana.y < me.y - 2.0, "behind the new aim (north): %s" % str(_pos(ana)))
	_free(ctx)


# ---------------------------------------------------------------- search --

func test_a_squad_member_asked_to_search_goes_there_searches_and_comes_back_to_follow() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	_at(ctx.me, 9.5, 8.5)
	var r: Dictionary = run.request(dez, "search", {"at": Vector2(16.5, 5.5)})
	check(r.ok, "Dez will: %s" % str(r))
	_step(run, 14.0)
	check(run.container("c1").looted, "the cabinet is searched")
	eq(int(run.carried.get("food", 0)), 10, "its food is in the bags")
	_step(run, 1.0)
	eq(dez.stance, "follow", "and he is back to following")
	eq(run.searching_of(dez), "", "not searching")
	_free(ctx)


func test_search_pauses_while_the_searcher_has_something_in_their_sights() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	_at(ctx.me, 15.5, 8.5)
	_at(dez, 16.5, 6.5)
	dez.stance = "search"
	dez.stance_at = Vector2(16.5, 6.5)
	var z = _post_dead(run, 19.5, 6.5)
	run.sim.radio.set_stance(dez, "search", Vector2(16.5, 6.5))
	_step(run, 0.1)
	_step(run, 3.0)
	check(float(run.container("c1").progress) < 1.0, "no progress while shooting: %f" % float(run.container("c1").progress))
	run.sim._hurt_zombie(z, 5000.0, 0.0, dez)
	_step(run, 6.0)
	check(run.container("c1").looted, "and it is finished when the target is down")
	_free(ctx)


func test_a_new_stance_while_searching_ends_the_search() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	_at(ctx.me, 16.5, 8.5)
	_at(dez, 16.5, 7.5)
	check(run.request(dez, "search", {"at": Vector2(16.5, 5.5)}).ok, "searching")
	_step(run, 4.0)
	eq(run.searching_of(dez), "c1", "on the cabinet")
	check(run.request(dez, "hold", {"at": Vector2(18.5, 8.5)}).ok, "then asked to hold")
	_step(run, 4.0)
	eq(run.searching_of(dez), "", "the search is over")
	eq(dez.stance, "hold", "he holds")
	check(not run.container("c1").looted, "unfinished")
	_free(ctx)


# ------------------------------------------------------------------ back --

func test_back_walks_to_the_exit_and_waits_there() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	_at(ctx.me, 12.5, 8.5)
	_at(dez, 12.0, 9.0)
	check(run.request(dez, "back").ok, "Dez goes back")
	_step(run, 9.0)
	eq(dez.stance, "back", "waiting at the exit")
	check(Rect2(site_exit(run)).has_point(_pos(dez)), "inside the exit rectangle: %s" % str(_pos(dez)))
	var at := _pos(dez)
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(30.5, 8.5), false)
	_step(run, 2.0)
	check(_pos(dez).distance_to(at) < 0.1, "the player walking off does not take him")
	_free(ctx)


func site_exit(run) -> Rect2:
	return run.site.exit


# ----------------------------------------------------------- stop to fire --

func test_a_person_with_a_target_in_sight_stops_to_fire_and_goes_on_a_second_after_it_is_down() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var dez = run.squad[1]
	var ana = run.squad[2]
	_at(me, 3.5, 4.5)
	_at(dez, 3.0, 4.5)
	_at(ana, 2.0, 11.5)
	var z = _post_dead(run, 8.5, 4.5)
	# the player walks away to the south: a follower who is not shooting would go after them
	run.sim.avatar.set_input(Vector2(0, 1), Vector2(3.5, 20.5), false)
	var shots0: int = dez.stats.shots
	var ammo0: float = run.sim.stock.ammo
	var at := _pos(dez)
	_step(run, 0.4)
	at = _pos(dez)
	_step(run, 3.0)
	check(_pos(dez).distance_to(at) < 0.05, "Dez stands where he is while he has the target: moved %f" % _pos(dez).distance_to(at))
	check(dez.stats.shots > shots0, "and fires: %d" % int(dez.stats.shots))
	check(run.sim.stock.ammo < ammo0, "at a cost")
	check(_pos(dez).distance_to(_pos(me)) > 3.0, "while the player is well away")
	# put it down
	run.sim._hurt_zombie(z, 5000.0, 0.0, dez)
	_step(run, 0.5)
	var held := _pos(dez)
	_step(run, 0.3)
	check(_pos(dez).distance_to(held) < 0.05, "he does not go the moment it is down")
	_step(run, 2.5)
	check(_pos(dez).distance_to(held) > 0.8, "a second later he is after the player: %s" % str(_pos(dez)))
	_free(ctx)


func test_a_person_does_not_stop_for_what_they_cannot_see() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var dez = run.squad[1]
	_at(me, 11.5, 8.5)
	_at(dez, 11.0, 8.5)
	var z = _post_dead(run, 19.5, 5.5)    # behind the house's wall
	run.sim.avatar.set_input(Vector2(0, 1), Vector2(11.5, 30.5), false)
	var at := _pos(dez)
	_step(run, 2.0)
	check(_pos(dez).distance_to(at) > 1.5, "Dez goes with the player: the dead behind the wall are not a target")
	check(z.state != "dying" and z.state != "dead", "and nothing shot it")
	_free(ctx)


# -------------------------------------------------------------- requests --

func test_a_request_goes_through_the_radio_with_its_refusals_and_its_lines() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	var r: Dictionary = run.request(dez, "come")
	check(r.ok and String(r.line) != "", "agreed, with a line: %s" % str(r))
	run.update(DT)
	check(_count(run, "radio_line") >= 1, "the line is an event for the scene")
	r = run.request("dez", "hold")
	check(r.ok, "a contact can be named by id")
	dez.downed = true
	r = run.request(dez, "come")
	check(not r.ok, "a downed man does not come")
	check(String(r.why).contains("down"), "and the reason is shown: %s" % String(r.why))
	r = run.request(ctx.me, "come")
	check(not r.ok and String(r.why).contains("you"), "nobody asks the player: %s" % String(r.why))
	r = run.request("nobody", "come")
	check(not r.ok and String(r.why) != "", "an unknown name is refused with a word")
	_free(ctx)


func test_search_that_needs_a_container_and_a_free_one() -> void:
	var ctx := _run()
	var run = ctx.run
	var ana = run.squad[2]
	var r: Dictionary = run.request(ana, "search", {"at": Vector2(9.5, 3.5)})
	check(not r.ok, "nothing to search there")
	eq(String(r.why), "Nothing to search there", "and it says so")
	eq(ana.stance, "follow", "Ana keeps following")
	run.container("c1")["looted"] = true
	r = run.request(ana, "search", {"at": Vector2(16.5, 5.5)})
	check(not r.ok and String(r.why).to_lower().contains("searched"), "a searched one: %s" % String(r.why))
	# the player is on the other one: nobody else joins them
	_at(ctx.me, 21.5, 9.5)
	check(ctx.run.begin_search(ctx.me, "c2"), "the player begins on the shelf")
	r = run.request(ana, "search", {"at": Vector2(21.5, 10.5)})
	check(not r.ok and String(r.why) != "", "somebody is on it already: %s" % String(r.why))
	# with no point given it is the one under the player's aim
	run.stop_search(ctx.me)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(21.5, 10.5), false)
	r = run.request(ana, "search")
	check(r.ok, "the player's aim names it: %s" % str(r))
	_free(ctx)


func test_to_the_walls_makes_no_sense_in_a_place_and_says_so() -> void:
	var ctx := _run()
	var run = ctx.run
	var r: Dictionary = run.request(run.squad[1], "post")
	check(not r.ok and String(r.why) != "", "refused with a reason: %s" % String(r.why))
	_free(ctx)


func test_a_request_is_refused_once_the_trip_is_turning_back() -> void:
	var ctx := _run()
	var run = ctx.run
	run.retreat()
	var r: Dictionary = run.request(run.squad[1], "hold", {"at": Vector2(8.5, 8.5)})
	check(not r.ok and String(r.why) != "", "refused: %s" % String(r.why))
	_free(ctx)


func test_the_old_orders_still_work_for_everyone_but_the_player() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	check(run.order_move(dez, Vector2(9.5, 3.5)), "Dez is ordered to a spot")
	eq(dez.stance, "", "and the order replaces what he was asked")
	_step(run, 5.0)
	check(_pos(dez).distance_to(Vector2(9.5, 3.5)) < 0.2, "he goes there")
	_at(ctx.me, 3.5, 10.5)
	_step(run, 4.0)
	check(_pos(dez).distance_to(Vector2(9.5, 3.5)) < 0.2, "and stays: an order is an order (the stance does not take him back)")
	var ana = run.squad[2]
	check(run.order_search(ana, "c1"), "Ana is sent to search")
	_step(run, 20.0)
	check(run.container("c1").looted, "and does")
	_free(ctx)


func test_a_squad_with_no_player_is_the_old_squad() -> void:
	var ctx := _run([], 3, false)
	var run = ctx.run
	check(run.avatar() == null, "no avatar")
	for p in run.squad:
		eq(p.stance, "", "%s has no stance" % p.first)
	var before: Array = []
	for p in run.squad:
		before.append(_pos(p))
	_step(run, 5.0)
	for i in run.squad.size():
		check(_pos(run.squad[i]).distance_to(before[i]) < 0.3, "%s stays put" % run.squad[i].first)
		eq(run.squad[i].stance, "", "and is never given a stance")
	check(run.order_move(run.squad[0], Vector2(8.5, 8.5)), "every one can be ordered")
	_free(ctx)


# ------------------------------------------------------------- succession --

func test_when_the_avatar_goes_down_the_most_trusted_of_the_squad_takes_over() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var dez = run.squad[1]
	var ana = run.squad[2]
	dez.trust = 60.0
	ana.trust = 75.0
	me.hp = 0.0
	run.sim.medical.on_downed(me, "bite")
	run.update(DT)
	check(run.avatar() == ana, "Ana leads now (the most trusted)")
	check(ana.player and not me.player, "the flag moved")
	eq(run.sim.player_id, String(ana.id), "the sim knows")
	near(ana.trust, 65.0, 0.001, "everyone trusts the player ten less")
	near(dez.trust, 50.0, 0.001, "Dez too")
	check(_count(run, "succession") == 1, "a succession event for the scene")
	check(not run.finished(), "the trip goes on")
	check(run.result().lost.has(String(me.id)), "the one who fell is lost")
	# the new leader is nobody's follower, and the old one is not anybody's leader
	eq(ana.stance, "", "Ana has no stance")
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(10.5, 8.5), false)
	var x0: float = ana.x
	_step(run, 1.0)
	check(ana.x > x0 + 2.0, "and walks by her own hands")
	_free(ctx)


func test_the_followers_follow_the_new_leader_after_a_succession() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var dez = run.squad[1]
	var ana = run.squad[2]
	dez.trust = 80.0
	ana.trust = 60.0
	_at(me, 3.5, 8.5)
	me.downed = true
	run.update(DT)
	check(run.avatar() == dez, "Dez leads")
	_at(ana, 2.5, 8.0)
	run.sim.avatar.set_input(Vector2(1, 0), Vector2(20.5, 8.5), false)
	_step(run, 3.0)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(20.5, 8.5), false)
	_step(run, 3.0)
	check(_pos(ana).distance_to(_pos(dez)) <= 2.3, "Ana followed Dez: %f" % _pos(ana).distance_to(_pos(dez)))
	check(_pos(ana).distance_to(_pos(me)) > 5.0, "and left the one who fell where they lay")
	_free(ctx)


func test_on_avatar_down_is_for_the_scene_and_does_nothing_while_they_stand() -> void:
	var ctx := _run()
	var run = ctx.run
	check(run.on_avatar_down() == ctx.me, "still the leader while they stand")
	ctx.me.downed = true
	var nxt = run.on_avatar_down()
	check(nxt != null and nxt != ctx.me and nxt.player, "the next leads: %s" % str(nxt))
	check(run.on_avatar_down() == nxt, "asking again changes nothing")
	_free(ctx)


func test_a_dead_avatar_hands_over_too_and_the_old_one_can_be_got_up_to_follow() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	me.downed = true
	run.update(DT)
	var lead = run.avatar()
	check(lead != me, "somebody else leads")
	_at(me, 8.5, 8.5)
	_at(lead, 9.1, 8.5)
	check(run.begin_help(lead, me), "the new leader gets them up")
	_step(run, RaidRun.HELP_S + 0.5)
	check(not me.downed, "up")
	_step(run, 0.2)
	eq(me.stance, "follow", "and follows the new leader")
	_free(ctx)


func test_with_nobody_left_standing_the_run_ends_and_says_so() -> void:
	var ctx := _run()
	var run = ctx.run
	run.carried = {"food": 12}
	for p in run.squad:
		p.downed = true
	run.update(DT)
	check(run.finished(), "nobody can go on")
	var r: Dictionary = run.result()
	eq(r.lost.size(), 3, "all three are lost")
	check(r.loot.is_empty(), "nothing comes home")
	check(run.on_avatar_down() == null, "and there is nobody to hand over to")
	_free(ctx)


func test_a_lone_avatar_who_falls_ends_the_trip() -> void:
	var ctx := _run([], 1)
	var run = ctx.run
	ctx.me.downed = true
	run.update(DT)
	check(run.finished(), "the trip is over")
	eq(run.result().lost.size(), 1, "and they are lost")
	_free(ctx)


# ----------------------------------------------------------------- result --

func test_the_result_carries_health_skills_trust_and_the_leader() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	var dez = run.squad[1]
	var ana = run.squad[2]
	dez.hp = 64.0
	run.sim.skills.credit(dez, "kills", 100.0)
	run.sim.skills.credit(dez, "melee", 1.0)
	run.sim.skills.credit(dez, "treated", 3.0)
	ana.downed = true
	var r: Dictionary = run.result()
	for k in ["loot", "hurt", "lost", "ammo_used", "beats", "hp", "skills", "trust_delta"]:
		check(r.has(k), "the result has %s" % k)
	eq(String(r.get("leader", "")), String(me.id), "the leader is named")
	near(float(r.hp.get(String(dez.id), -1.0)), 64.0, 0.001, "Dez's health as he leaves")
	check(r.hp.has(String(me.id)), "and the player's")
	check(not r.hp.has(String(ana.id)), "but not a lost one's")
	check(r.lost.has(String(ana.id)), "Ana is lost: she is down")
	eq(int(r.skills.get(String(dez.id), {}).get("Shooting", 0)), 1, "a hundred kills is a point of Shooting")
	check(not r.skills.get(String(dez.id), {}).has("Leading"), "Leading never grows")
	check(not r.skills.has(String(ana.id)), "a lost one brings nothing home")
	near(float(r.trust_delta.get(String(dez.id), -99.0)), 2.0, 0.001, "Dez came home having followed: two more")
	check(not r.trust_delta.has(String(ana.id)) or float(r.trust_delta[String(ana.id)]) == 0.0, "Ana, lost: nothing")
	_free(ctx)


func test_someone_left_to_hold_or_to_wait_earns_no_trust() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	run.sim.radio.set_stance(dez, "hold", Vector2(_pos(dez)))
	var r: Dictionary = run.result()
	near(float(r.trust_delta.get(String(dez.id), -99.0)), 0.0, 0.001, "a man left holding did not follow")
	near(float(r.trust_delta.get(String(run.squad[2].id), -99.0)), 2.0, 0.001, "while Ana did")
	_free(ctx)


func test_the_skills_in_the_result_cap_at_the_most_a_run_may_give() -> void:
	var ctx := _run()
	var run = ctx.run
	var dez = run.squad[1]
	for k in 4:
		run.sim.skills.credit(dez, "melee", 500.0)
	var r: Dictionary = run.result()
	check(int(r.skills.get(String(dez.id), {}).get("Melee", 0)) <= 3, "at most three points")
	_free(ctx)


func test_a_person_keeps_the_colony_id_and_brings_their_trust_and_no_stance() -> void:
	var g := Helpers.make(3, 1, 6)
	var colony = g.sim
	var dez = null
	for p in colony.people:
		if p.id == "dez":
			dez = p
	dez.trust = 71.0
	dez.stance = "hold"
	dez.stance_at = Vector2(40, 40)
	var site := _site()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var run = RaidRun.new(site, world, FxNull.new(), RaidRun.squad_of([dez]), 300.0)
	var q = run.squad[0]
	eq(String(q.id), "dez", "the colony's id")
	near(q.trust, 71.0, 0.001, "their trust in the player comes with them")
	eq(q.stance, "", "the stance is cleared")
	eq(q.stance_at, Vector2.ZERO, "and so is its spot")
	world.free()
	g.world.free()


# ------------------------------------------------------------ time and light --

func test_the_place_has_the_colonys_clock_and_the_dead_hunt_at_night() -> void:
	var ctx := _run([{"pos": Vector2(8.5, 8.5), "kind": "walker", "state": "still"}], 2)
	var run = ctx.run
	var colony = ctx.g.sim
	colony.minutes = 23.0 * 60.0 + 30.0
	colony.phase = colony.phase_at(colony.minutes)
	colony.bell_rung = true
	run.mirror(colony)
	near(run.hour(), 23.5, 0.001, "the hour is the colony's")
	check(run.is_night(), "and it is night")
	var z = run.sim.zombies[0]
	_step(run, 6.0)
	check(z.state == "hunt" or z.state == "dying" or z.state == "dead", "the dead of the place hunt at night: %s" % z.state)
	# the squad fires at night as by day, the avatar too
	var me = ctx.me
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(8.5, 8.5), true)
	_step(run, 3.0)
	check(me.stats.shots > 0 or run.squad[1].stats.shots > 0, "somebody shot")
	_free(ctx)


func test_a_place_with_no_base_to_mirror_has_a_morning() -> void:
	var ctx := _run([], 1)
	var h: float = ctx.run.hour()
	check(h > 6.0 and h < 18.0, "an ordinary day's hour: %f" % h)
	check(not ctx.run.is_night(), "not night")
	_free(ctx)


# ----------------------------------------------------------------- retreat --

func test_retreat_leaves_the_avatar_to_walk_out_by_hand_and_the_run_ends_when_they_are_out() -> void:
	var ctx := _run()
	var run = ctx.run
	var me = ctx.me
	_at(me, 20.5, 8.5)
	run.retreat()
	eq(run.phase, "retreat", "turning back")
	check(me.order == null, "the avatar was not ordered")
	_step(run, 12.0)
	for k in [1, 2]:
		check(run.site.exit.grow(RaidRun.OUT_SLACK).has_point(_pos(run.squad[k])), "%s is at the exit" % run.squad[k].first)
	check(not run.finished(), "the run waits for the player")
	run.sim.avatar.set_input(Vector2(-1, 0), Vector2(0.5, 8.5), false)
	_step(run, 6.0)
	check(run.finished(), "they are out: the run is over")
	_free(ctx)
