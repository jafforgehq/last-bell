extends "res://tests/case.gd"
## The avatar (round 17, scripts/sim/avatar.gd): the person the player plays, in the simulation. WASD movement with
## collision, aimed fire along a ray, reload, melee, succession when they are lost, and that the AI leaves them alone.
## The views (input, drawing) are not here: they feed `sim.avatar.set_input` and read the person.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const Helpers := preload("res://tests/helpers.gd")

const DT := 1.0 / 30.0
## The arena: open ground in the yard, carved free of props for the tests that need clear lines.
const ARENA := Rect2i(34, 26, 20, 12)


## Records what the rules draw, so that the tests can read where shots went.
class RecFx:
	extends FxNull
	var tracers: Array = []
	var muzzles: Array = []

	func tracer(x0: float, y0: float, x1: float, y1: float) -> void:
		tracers.append([Vector2(x0, y0), Vector2(x1, y1)])

	func muzzle(x: float, y: float, ang: float, big: bool) -> void:
		muzzles.append({"at": Vector2(x, y), "ang": ang, "big": big})


# ----------------------------------------------------------------- helpers --

func _person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## A game with the avatar (Ruth, or `who`) standing at (40.5, 30.5) in a clear arena, the dead cleared away, nobody
## working, the gun given and loaded, the recorder drawing.
func _game(weapon: String = "rifle", who: String = "ruth") -> Dictionary:
	var g := Helpers.make(7, 1, 6)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.zombies.clear()
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			g.world.solid_p[ty * g.world.W + tx] = 0
			g.world.solid_z[ty * g.world.W + tx] = 0
	var rec := RecFx.new()
	sim.fx = rec
	var p = _person(sim, who)
	check(sim.avatar.set_player(p), "%s is the player" % who)
	p.weapon = weapon
	p.gun = sim.weapons[weapon]
	p.mag = int(p.gun.get("mag", 0))
	p.x = 40.5
	p.y = 30.5
	p.cooldown = 0.0
	p.reloading = 0.0
	g["p"] = p
	g["rec"] = rec
	return g


func _wall(g: Dictionary, x: int, y0: int, y1: int) -> void:
	for ty in range(y0, y1 + 1):
		g.world.solid_p[ty * g.world.W + x] = 1
		g.world.solid_z[ty * g.world.W + x] = 1


## One of the dead standing still at a spot (it does not move until it is hurt).
func _dead_at(sim, x: float, y: float, hp: float = 1.0, kind: String = "walker"):
	var z = sim.spawn(x, y, "wander", kind)
	z.hp = hp
	z.stagger = 1.0e6
	z.limp = false
	return z


func _step(sim, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		sim.update(DT)


func _count(sim, type: String) -> int:
	var n := 0
	for e in sim.events:
		if e.get("type", "") == type:
			n += 1
	return n


func _alive(z) -> bool:
	return z.state != "dying" and z.state != "dead"


# ---------------------------------------------------------------- the player --

func test_nobody_is_the_player_in_the_old_game() -> void:
	var g := Helpers.make(1, 1)
	eq(g.sim.player_id, "", "no player in a game made the old way")
	check(g.sim.avatar.player() == null, "and no avatar")
	for p in g.sim.people:
		check(not p.player, "%s is not the player" % p.id)
		near(p.trust, 55.0, 0.0001, "trust starts at 55")
		eq(p.stance, "", "no stance")
	g.world.free()


func test_a_person_is_made_the_player_by_id_or_by_object_and_only_one_is() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	check(sim.avatar.set_player("dez"), "by id")
	eq(sim.player_id, "dez", "the sim knows")
	check(sim.avatar.player() == _person(sim, "dez"), "player() is Dez")
	check(_person(sim, "dez").player, "flagged")
	check(sim.avatar.set_player(_person(sim, "ana")), "by object")
	eq(sim.player_id, "ana", "now Ana")
	check(not _person(sim, "dez").player and _person(sim, "ana").player, "only one flag is set")
	check(not sim.avatar.set_player("nobody"), "an unknown id is refused")
	eq(sim.player_id, "ana", "and nothing changes")
	_person(sim, "marcus").dead = true
	check(not sim.avatar.set_player("marcus"), "a dead person cannot be the player")
	sim.avatar.set_player(null)
	eq(sim.player_id, "", "null gives the avatar up")
	check(not _person(sim, "ana").player, "and clears the flag")
	g.world.free()


func test_set_input_goes_to_the_player_and_nobody_else() -> void:
	var g := _game()
	var sim = g.sim
	sim.avatar.set_input(Vector2(1, 0), Vector2(50, 30), true)
	eq(g.p.input_move, Vector2(1, 0), "the move")
	eq(g.p.input_aim, Vector2(50, 30), "the aim")
	check(g.p.input_fire, "the trigger")
	for q in sim.people:
		if q != g.p:
			eq(q.input_move, Vector2.ZERO, "%s is not moved" % q.id)
			check(not q.input_fire, "%s does not fire" % q.id)
	g.world.free()


# ------------------------------------------------------------------ movement --

func test_the_avatar_walks_at_three_point_two_tiles_a_second() -> void:
	var g := _game()
	var p = g.p
	g.sim.avatar.set_input(Vector2(1, 0), Vector2(60, 30.5), false)
	_step(g.sim, 1.0)
	near(p.x, 40.5 + 3.2, 0.02, "three point two tiles east in a second")
	near(p.y, 30.5, 0.001, "and none sideways")
	check(p.moving, "moving")
	check(p.walk_phase > 0.0, "the walk animation runs")
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(60, 30.5), false)
	_step(g.sim, 0.2)
	check(not p.moving, "standing once the keys are let go")
	g.world.free()


func test_a_diagonal_is_not_faster() -> void:
	var g := _game()
	var p = g.p
	g.sim.avatar.set_input(Vector2(1, 1), Vector2(60, 40), false)
	_step(g.sim, 1.0)
	near(Vector2(p.x - 40.5, p.y - 30.5).length(), 3.2, 0.03, "a second diagonally is the same distance")
	near(p.x - 40.5, p.y - 30.5, 0.001, "equally east and south")
	g.sim.avatar.set_input(Vector2(5, 0), Vector2(60, 40), false)
	var x0: float = p.x
	_step(g.sim, 0.5)
	near(p.x - x0, 1.6, 0.02, "a long vector does not run: it is the direction that counts")
	g.world.free()


func test_a_wall_stops_the_avatar_a_radius_short_of_it() -> void:
	var g := _game()
	var p = g.p
	_wall(g, 45, 26, 37)
	g.sim.avatar.set_input(Vector2(1, 0), Vector2(60, 30.5), false)
	_step(g.sim, 3.0)
	near(p.x, 45.0 - 0.3, 0.01, "against the wall, a radius (0.3) short of it")
	check(not p.moving, "not walking on the spot")
	g.world.free()


func test_the_avatar_slides_along_a_wall_when_it_pushes_diagonally() -> void:
	var g := _game()
	var p = g.p
	_wall(g, 45, 26, 37)
	g.sim.avatar.set_input(Vector2(1, 1), Vector2(60, 40), false)
	_step(g.sim, 2.5)
	near(p.x, 45.0 - 0.3, 0.01, "held off the wall")
	check(p.y > 34.0, "and carried south along it: %f" % p.y)
	check(p.moving, "still walking")
	g.world.free()


func test_a_solid_prop_of_the_yard_stops_the_avatar() -> void:
	# two crates at (43, 25) and (44, 25) in the real map: shut tiles
	var g := Helpers.make(7, 1, 6)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.zombies.clear()
	var w: int = g.world.W
	check(g.world.solid_p[25 * w + 43] != 0 and g.world.solid_p[25 * w + 44] != 0, "the premise: crates at (43, 25) and (44, 25)")
	check(g.world.solid_p[27 * w + 43] == 0 and g.world.solid_p[26 * w + 43] == 0, "and open ground south of them")
	var p = _person(sim, "ruth")
	sim.avatar.set_player(p)
	p.x = 43.9
	p.y = 28.5
	sim.avatar.set_input(Vector2(0, -1), Vector2(43.9, 20), false)
	_step(sim, 2.0)
	near(p.y, 26.0 + 0.3, 0.02, "stopped at the crate's edge")
	near(p.x, 43.9, 0.001, "straight")
	g.world.free()


func test_the_edge_of_the_map_stops_the_avatar() -> void:
	var g := _game()
	var p = g.p
	p.x = 0.8
	p.y = 5.5    # (the map's own edge has a margin of shut ground at (0, 30): here it is open to the edge)
	g.sim.avatar.set_input(Vector2(-1, 0), Vector2(0, 5.5), false)
	_step(g.sim, 1.0)
	near(p.x, 0.3, 0.01, "stopped at the map's edge, a radius in")
	g.world.free()


func test_no_tunnelling_through_a_one_tile_wall_at_thirty_steps_a_second() -> void:
	var g := _game()
	var p = g.p
	_wall(g, 45, 26, 37)
	var worst := 0.0
	g.sim.avatar.set_input(Vector2(1, 0.3), Vector2(60, 30.5), false)
	for i in 400:
		g.sim.update(DT)
		worst = maxf(worst, p.x)
		if i % 100 == 99:
			p.y = 30.5    # (kept in the arena)
	check(worst < 45.0 - 0.29 + 0.001, "never in the wall: %f" % worst)
	g.world.free()


func test_no_tunnelling_with_a_huge_step_either() -> void:
	var g := _game()
	var p = g.p
	_wall(g, 45, 26, 37)
	g.sim.avatar.set_input(Vector2(1, 0), Vector2(60, 30.5), false)
	for i in 20:
		g.sim.avatar.update(p, 0.5)    # a step of 1.6 tiles
	check(p.x < 45.0 - 0.29 + 0.001, "a half-second step does not jump the wall: %f" % p.x)
	g.world.free()


func test_someone_standing_a_hair_inside_a_wall_is_pushed_out_and_not_let_through() -> void:
	var g := _game()
	var p = g.p
	_wall(g, 45, 26, 37)
	p.x = 44.8    # 0.1 inside the avatar's reach of the wall
	g.sim.avatar.set_input(Vector2(1, 0), Vector2(60, 30.5), false)
	_step(g.sim, 2.0)
	check(p.x < 45.0 - 0.29 + 0.001, "pushed out of the wall, and not through it: %f" % p.x)
	g.world.free()


func test_the_avatar_faces_and_aims_at_the_mouse() -> void:
	var g := _game()
	var p = g.p
	var sim = g.sim
	sim.avatar.set_input(Vector2.ZERO, Vector2(p.x + 6.0, p.y), false)
	_step(sim, 0.1)
	eq(p.facing, "E", "east")
	near(p.aim, 0.0, 0.06, "the aim points east")
	sim.avatar.set_input(Vector2.ZERO, Vector2(p.x - 6.0, p.y), false)
	_step(sim, 0.1)
	eq(p.facing, "W", "west")
	near(absf(p.aim), PI, 0.06, "the aim points west")
	sim.avatar.set_input(Vector2.ZERO, Vector2(p.x, p.y - 6.0), false)
	_step(sim, 0.1)
	eq(p.facing, "N", "north")
	near(p.aim, -PI / 2.0, 0.1, "the aim points north")
	sim.avatar.set_input(Vector2.ZERO, Vector2(p.x, p.y + 6.0), false)
	_step(sim, 0.1)
	eq(p.facing, "S", "south")
	near(p.aim, PI / 2.0, 0.1, "the aim points south")
	# walking one way while aiming the other: the aim is the mouse's, not the walk's
	sim.avatar.set_input(Vector2(-1, 0), Vector2(p.x + 6.0, p.y), false)
	_step(sim, 0.3)
	eq(p.facing, "E", "facing the mouse while walking west")
	g.world.free()


func test_the_avatar_does_not_walk_to_a_post_or_a_job_by_itself() -> void:
	var g := _game()
	var p = g.p
	g.sim.tactics.chores = true
	g.sim.jobs.auto_assign()
	var at := Vector2(p.x, p.y)
	g.sim.minutes = 21.5 * 60.0    # night: the crew goes to its posts
	_step(g.sim, 6.0)
	near(Vector2(p.x, p.y).distance_to(at), 0.0, 0.001, "still where the player left them")
	check(p.order == null, "with no order of the AI")
	g.world.free()


func test_orders_to_the_avatar_are_refused() -> void:
	var g := _game()
	var p = g.p
	check(not g.sim.order_move(p, 41.5, 31.5), "no one orders the player about")
	check(p.order == null and not p.drafted, "and nothing is set")
	g.sim.order_post(p)
	g.sim.toggle_draft(p)
	g.sim.order_repair(p, g.sim.segments[0])
	check(p.order == null and not p.drafted and p.repair == null, "not by post, draft or repair either")
	g.world.free()


func test_a_downed_avatar_does_not_move_or_shoot() -> void:
	var g := _game()
	var p = g.p
	var z = _dead_at(g.sim, 45.5, 30.5)
	p.hp = 0.0
	g.sim.medical.on_downed(p, "bite")
	g.sim.avatar.set_input(Vector2(1, 0), Vector2(45.5, 30.5), true)
	_step(g.sim, 1.0)
	near(p.x, 40.5, 0.001, "down: not walking")
	check(_alive(z), "nor shooting")
	eq(_count(g.sim, "shot"), 0, "no shot was heard")
	g.world.free()


# ---------------------------------------------------------------- aimed fire --

func test_a_shot_kills_the_dead_in_front_of_the_muzzle() -> void:
	var g := _game("rifle")
	var p = g.p
	var z = _dead_at(g.sim, 46.5, 30.5, 1.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 0.1)
	check(not _alive(z), "the dead one is down")
	eq(p.mag, int(p.gun.mag) - 1, "one round gone from the magazine")
	eq(_count(g.sim, "shot"), 1, "one shot was heard")
	eq(g.sim.kills, 1, "and counted")
	eq(int(p.stats.kills), 1, "credited to the avatar")
	check(p.cooldown > 0.3, "the rifle must cool: %f" % p.cooldown)
	g.world.free()


func test_a_shot_misses_the_dead_off_the_line() -> void:
	var g := _game("rifle")
	var z = _dead_at(g.sim, 46.5, 33.5, 1.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 0.1)
	check(_alive(z), "three tiles off the line: untouched")
	near(z.hp, 1.0, 0.0001, "unhurt")
	eq(_count(g.sim, "shot"), 1, "but the shot was fired")
	g.world.free()


func test_a_shot_hits_the_nearest_of_the_dead_in_line_and_no_more() -> void:
	var g := _game("rifle")
	var near_z = _dead_at(g.sim, 44.5, 30.5, 1.0)
	var far_z = _dead_at(g.sim, 48.5, 30.5, 1.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(48.5, 30.5), true)
	_step(g.sim, 0.1)
	check(not _alive(near_z), "the near one takes it")
	check(_alive(far_z), "nothing goes through to the far one")
	near(far_z.hp, 1.0, 0.0001, "unhurt")
	g.world.free()


func test_a_shot_does_not_reach_past_the_guns_range() -> void:
	var g := _game("pistol")    # nine tiles
	var z = _dead_at(g.sim, 40.5 + 11.0, 30.5, 1.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(z.x, z.y), true)
	_step(g.sim, 0.1)
	check(_alive(z), "eleven tiles is past a pistol")
	g.world.free()


func test_a_wall_stops_a_shot() -> void:
	var g := _game("rifle")
	_wall(g, 43, 26, 37)
	var behind = _dead_at(g.sim, 47.5, 30.5, 1.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(47.5, 30.5), true)
	_step(g.sim, 0.1)
	check(_alive(behind), "the dead behind a wall are not shot")
	var last: Array = g.rec.tracers[g.rec.tracers.size() - 1]
	check(last[1].x < 43.5, "the tracer ends at the wall: %s" % str(last[1]))
	var before = _dead_at(g.sim, 42.2, 30.5, 1.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(42.2, 30.5), true)
	_step(g.sim, 0.7)
	check(not _alive(before), "but the one in front of it is")
	g.world.free()


func test_a_shot_goes_over_a_wall_section_from_the_walkway() -> void:
	# the north wall's sections are low barricades: from the walkway above the yard the dead at the wall are shot over them
	var g := Helpers.make(7, 1, 6)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.zombies.clear()
	var w: int = g.world.W
	check(g.world.solid_p[16 * w + 45] != 0 and g.world.deck_tiles.has(18 * w + 45), "the premise: a section at (45, 16) and the walkway at (45, 18)")
	var p = _person(sim, "walt")
	p.weapon = "rifle"
	p.gun = sim.weapons.rifle
	p.mag = 8
	sim.avatar.set_player(p)
	p.x = 45.5
	p.y = 18.5
	p.cooldown = 0.0
	var z = _dead_at(sim, 45.5, 13.5, 1.0)
	sim.avatar.set_input(Vector2.ZERO, Vector2(45.5, 13.5), true)
	_step(sim, 0.1)
	check(not _alive(z), "shot over the wall")
	g.world.free()


func test_the_walkways_face_stops_a_shot_from_the_yard_floor() -> void:
	# from the ground the walkway hangs in the way: to shoot over the wall, go up a ladder
	var g := Helpers.make(7, 1, 6)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.zombies.clear()
	var w: int = g.world.W
	check(g.world.solid_p[20 * w + 45] != 0, "the premise: the walkway's face at (45, 20)")
	var p = _person(sim, "walt")
	p.weapon = "rifle"
	p.gun = sim.weapons.rifle
	p.mag = 8
	sim.avatar.set_player(p)
	p.x = 45.5
	p.y = 23.5
	p.cooldown = 0.0
	var z = _dead_at(sim, 45.5, 13.5, 1.0)
	sim.avatar.set_input(Vector2.ZERO, Vector2(45.5, 13.5), true)
	_step(sim, 0.1)
	check(_alive(z), "stopped by the walkway")
	g.world.free()


func test_a_shot_costs_the_stock_and_a_shell_costs_more() -> void:
	var g := _game("rifle")
	g.sim.stock.ammo = 100.0
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 0.1)
	near(g.sim.stock.ammo, 100.0 - Sim.SHOT_COST, 0.0001, "a round of the rifle")
	g.world.free()
	var s := _game("shotgun")
	s.sim.stock.ammo = 100.0
	s.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(s.sim, 0.1)
	near(s.sim.stock.ammo, 100.0 - Sim.SHELL_COST, 0.0001, "a shell of the shotgun")
	s.world.free()


func test_with_the_stock_dry_the_butt_of_the_gun_is_what_is_swung() -> void:
	var g := _game("rifle")
	var p = g.p
	g.sim.stock.ammo = 0.1    # less than a round
	var z = _dead_at(g.sim, 41.9, 30.5, 5.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(41.9, 30.5), true)
	_step(g.sim, 0.1)
	eq(p.mag, int(p.gun.mag), "no round was fired")
	near(g.sim.stock.ammo, 0.1, 0.0001, "and none paid for")
	eq(_count(g.sim, "shot"), 0, "no shot is heard")
	check(_count(g.sim, "stab") >= 1, "a blow is struck")
	near(z.hp, 5.0 - Sim.BUTT.dmg, 0.0001, "with the butt's damage")
	g.world.free()


func test_the_shotguns_pellets_spread_in_a_cone() -> void:
	var g := _game("shotgun")
	var p = g.p
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(p.x + 8.0, p.y - 0.1), true)
	_step(g.sim, 0.05)
	eq(g.rec.tracers.size(), 5, "five pellets, five tracers")
	var lo := 10.0
	var hi := -10.0
	for t in g.rec.tracers:
		var a: float = (t[1] - t[0]).angle()
		lo = minf(lo, a)
		hi = maxf(hi, a)
	check(hi - lo > 0.03, "the pellets part: %f" % (hi - lo))
	check(hi - lo < 0.5, "but stay in a cone: %f" % (hi - lo))
	g.world.free()


func test_a_shotgun_blast_wounds_what_a_rifle_round_only_scratches() -> void:
	var g := _game("shotgun")
	var z = _dead_at(g.sim, 43.0, 30.5, 20.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(43.0, 30.5), true)
	_step(g.sim, 0.05)
	check(z.hp < 20.0 - 2.0 * float(g.p.gun.dmg), "several pellets landed: hp %f" % z.hp)
	g.world.free()


## The mean angle off the aim of `n` single shots with the given state before each.
func _scatter(weapon: String, n: int, recoil: float, moving: bool) -> float:
	var g := _game(weapon)
	var p = g.p
	var sim = g.sim
	var total := 0.0
	for i in n:
		p.cooldown = 0.0
		p.mag = int(p.gun.mag)
		p.reloading = 0.0
		p.recoil = recoil
		p.bloom = 0.0
		p.x = 40.5
		p.y = 30.5
		sim.stock.ammo = 400.0
		g.sim.avatar.set_input(Vector2(0, 1) if moving else Vector2.ZERO, Vector2(49.0, 30.5), true)
		g.rec.tracers.clear()
		sim.update(DT)
		for t in g.rec.tracers:
			total += absf(Sim.ang_diff(p.aim, (t[1] - t[0]).angle()))
	g.world.free()
	return total / float(n)


func test_recoil_widens_the_spread() -> void:
	var calm := _scatter("pistol", 150, 0.0, false)
	var kicked := _scatter("pistol", 150, 1.0, false)
	check(calm > 0.0, "a pistol is not a laser: %f" % calm)
	check(kicked > calm * 1.3, "kick throws the shots wider: %f against %f" % [kicked, calm])


func test_walking_widens_the_spread_too() -> void:
	var still := _scatter("pistol", 150, 0.0, false)
	var walking := _scatter("pistol", 150, 0.0, true)
	check(walking > still * 1.2, "walking spoils the aim: %f against %f" % [walking, still])


func test_the_avatar_fires_while_walking() -> void:
	var g := _game("rifle")
	var p = g.p
	var z = _dead_at(g.sim, 47.5, 31.5, 1.0)
	g.sim.avatar.set_input(Vector2(0, 1), Vector2(47.5, 31.5), true)
	_step(g.sim, 0.1)
	check(p.moving, "walking")
	check(not _alive(z), "and the shot killed it all the same")
	g.world.free()


func test_the_rifle_cannot_fire_faster_than_its_cooldown() -> void:
	var g := _game("rifle")
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 2.0)    # a half-second rifle, the trigger held
	var shots := _count(g.sim, "shot")
	check(shots >= 3 and shots <= 5, "about four shots in two seconds: %d" % shots)
	g.world.free()


func test_a_shot_draws_the_dead_of_the_streets() -> void:
	var g := _game("rifle")
	var z = _dead_at(g.sim, 60.0, 30.5, 5.0)
	z.state = "wander"
	g.sim.town.on = false
	g.sim.phase = "night"
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 0.1)
	check(z.state != "wander", "a straggler within hearing comes to the noise: %s" % z.state)
	g.world.free()


# -------------------------------------------------------------------- reload --

func test_reload_takes_the_weapons_time_and_refills_the_magazine() -> void:
	var g := _game("rifle")
	var p = g.p
	p.mag = 3
	g.sim.avatar.reload()
	_step(g.sim, 0.1)
	var need: float = float(p.gun.reload) * g.sim.traits.mult(p, "reload")
	check(p.reloading > 0.0 and p.reloading <= need, "reloading, %f of %f left" % [p.reloading, need])
	eq(p.mag, 3, "the magazine is not full yet")
	eq(_count(g.sim, "reload"), 1, "the reload is heard")
	_step(g.sim, need - 0.3)
	eq(p.mag, 3, "still not")
	_step(g.sim, 0.6)
	eq(p.mag, int(p.gun.mag), "refilled")
	near(p.reloading, 0.0, 0.0001, "done")
	g.world.free()


func test_no_firing_while_reloading() -> void:
	var g := _game("rifle")
	var p = g.p
	var z = _dead_at(g.sim, 46.5, 30.5, 1.0)
	p.mag = 3
	g.sim.avatar.reload()
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 1.0)
	check(_alive(z), "the trigger does nothing in the middle of a reload")
	eq(_count(g.sim, "shot"), 0, "no shot")
	_step(g.sim, 2.5)
	check(not _alive(z), "and the shot comes when it is done")
	g.world.free()


func test_a_reload_is_not_started_for_a_full_magazine_or_an_empty_stock() -> void:
	var g := _game("rifle")
	var p = g.p
	g.sim.avatar.reload()
	_step(g.sim, 0.1)
	near(p.reloading, 0.0, 0.0001, "a full magazine needs no reload")
	p.mag = 2
	g.sim.stock.ammo = 0.0
	g.sim.avatar.reload()
	_step(g.sim, 0.1)
	near(p.reloading, 0.0, 0.0001, "and with nothing in the stock there is nothing to load")
	g.world.free()


func test_the_last_round_starts_the_reload_by_itself() -> void:
	var g := _game("rifle")
	var p = g.p
	p.mag = 1
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 0.1)
	eq(p.mag, 0, "the magazine is empty")
	check(p.reloading > 0.0, "and the reload has begun")
	g.world.free()


func test_an_empty_magazine_reloads_when_the_trigger_is_let_go() -> void:
	var g := _game("rifle")
	var p = g.p
	p.mag = 0
	p.reloading = 0.0
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), true)
	_step(g.sim, 0.2)
	near(p.reloading, 0.0, 0.0001, "the trigger held: it only clicks")
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), false)
	_step(g.sim, 0.1)
	check(p.reloading > 0.0, "let go: the reload starts")
	g.world.free()


# --------------------------------------------------------------------- melee --

func test_a_melee_swing_hits_what_is_in_front_and_not_what_is_behind() -> void:
	var g := _game("rifle")
	var p = g.p
	var front = _dead_at(g.sim, 41.8, 30.5, 10.0)
	var behind = _dead_at(g.sim, 39.2, 30.5, 10.0)
	var side = _dead_at(g.sim, 40.5, 31.8, 10.0)
	var far = _dead_at(g.sim, 43.5, 30.5, 10.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), false)
	g.sim.avatar.melee()
	_step(g.sim, 0.1)
	near(front.hp, 10.0 - Sim.BUTT.dmg, 0.0001, "the one in front takes the butt")
	near(behind.hp, 10.0, 0.0001, "the one behind is untouched")
	near(side.hp, 10.0, 0.0001, "so is the one at the side, outside the arc")
	near(far.hp, 10.0, 0.0001, "and the one out of reach")
	check(_count(g.sim, "stab") == 1, "a stab is heard")
	check(p.thrust > 0.0, "the drawing thrusts")
	g.world.free()


func test_a_swing_hits_everyone_in_the_arc_once() -> void:
	var g := _game("rifle")
	var a = _dead_at(g.sim, 41.8, 30.5, 10.0)
	var b = _dead_at(g.sim, 41.6, 29.9, 10.0)
	var c = _dead_at(g.sim, 41.7, 31.3, 10.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), false)
	g.sim.avatar.melee()
	_step(g.sim, 0.1)
	for z in [a, b, c]:
		near(z.hp, 10.0 - Sim.BUTT.dmg, 0.0001, "all three are struck, once")
	g.world.free()


func test_the_swing_has_a_cooldown_and_needs_no_ammo() -> void:
	var g := _game("rifle")
	var z = _dead_at(g.sim, 41.8, 30.5, 50.0)
	g.sim.stock.ammo = 0.0
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), false)
	g.sim.avatar.melee()
	_step(g.sim, 0.2)
	g.sim.avatar.melee()
	_step(g.sim, 0.1)
	near(z.hp, 50.0 - Sim.BUTT.dmg, 0.0001, "the second swing, 0.3 s later, is too soon")
	_step(g.sim, 0.4)
	g.sim.avatar.melee()
	_step(g.sim, 0.1)
	near(z.hp, 50.0 - 2.0 * Sim.BUTT.dmg, 0.0001, "after half a second it lands again, with an empty stock")
	g.world.free()


func test_the_pike_swings_with_its_own_damage() -> void:
	var g := _game("pike")
	var z = _dead_at(g.sim, 41.8, 30.5, 10.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), false)
	g.sim.avatar.melee()
	_step(g.sim, 0.1)
	near(z.hp, 10.0 - float(g.p.gun.dmg), 0.0001, "the pike's blow")
	g.world.free()


func test_a_pike_thrusts_when_the_trigger_is_held() -> void:
	var g := _game("pike")
	var z = _dead_at(g.sim, 43.0, 30.5, 10.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(43.0, 30.5), true)
	_step(g.sim, 0.1)
	near(z.hp, 10.0 - float(g.p.gun.dmg), 0.0001, "the pike has a reach of its own: it needs no magazine")
	g.world.free()


func test_a_swing_does_not_go_through_a_wall() -> void:
	var g := _game("rifle")
	_wall(g, 41, 26, 37)
	var z = _dead_at(g.sim, 41.9, 30.5, 10.0)
	g.sim.avatar.set_input(Vector2.ZERO, Vector2(46.5, 30.5), false)
	g.sim.avatar.melee()
	_step(g.sim, 0.1)
	near(z.hp, 10.0, 0.0001, "the wall is between")
	g.world.free()


# ---------------------------------------------------------------- succession --

func test_when_the_player_dies_the_most_trusted_takes_over() -> void:
	var g := _game()
	var sim = g.sim
	for q in sim.people:
		q.trust = 55.0
	_person(sim, "dez").trust = 40.0
	_person(sim, "ana").trust = 90.0
	_person(sim, "walt").trust = 60.0
	sim.events.clear()
	sim.medical.kill(g.p, "bled out")
	eq(sim.player_id, "ana", "the most trusted is next")
	check(_person(sim, "ana").player, "Ana is the player")
	check(not g.p.player, "Ruth is not")
	var found := false
	for e in sim.events:
		if e.get("type", "") == "succession":
			found = true
			eq(e.from, "ruth", "from Ruth")
			eq(e.to, "ana", "to Ana")
	check(found, "a succession event is raised")
	near(_person(sim, "ana").trust, 80.0, 0.0001, "every living person's trust drops by ten")
	near(_person(sim, "dez").trust, 30.0, 0.0001, "Dez too")
	g.world.free()


func test_a_tie_in_trust_goes_to_the_better_leader_then_to_the_id() -> void:
	var g := _game()
	var sim = g.sim
	for q in sim.people:
		q.trust = 55.0
	_person(sim, "dez").skills["Leading"] = 4
	_person(sim, "ana").skills["Leading"] = 7
	_person(sim, "walt").skills["Leading"] = 7
	_person(sim, "marcus").skills["Leading"] = 2
	_person(sim, "hector").skills["Leading"] = 2
	sim.medical.kill(g.p, "bled out")
	eq(sim.player_id, "ana", "Leading 7, and Ana's id comes before Walt's")
	g.world.free()


func test_the_one_who_is_down_is_the_last_to_be_chosen() -> void:
	var g := _game()
	var sim = g.sim
	for q in sim.people:
		q.trust = 40.0
	var ana = _person(sim, "ana")
	ana.trust = 95.0
	ana.hp = 0.0
	sim.medical.on_downed(ana, "bite")
	sim.medical.kill(g.p, "bled out")
	check(sim.player_id != "ana" and sim.player_id != "", "someone who can stand takes over: %s" % sim.player_id)
	g.world.free()


func test_someone_away_is_next_in_line_only_when_nobody_is_at_the_base() -> void:
	# (round 17 review: a player who is away has no body to walk or shoot with and cannot ask anybody to come)
	var g := _game()
	var sim = g.sim
	for q in sim.people:
		q.trust = 40.0
	var dez = _person(sim, "dez")
	dez.trust = 95.0
	dez.away = {"kind": "party"}
	_person(sim, "ana").trust = 60.0
	sim.medical.kill(g.p, "bled out")
	eq(sim.player_id, "ana", "somebody at the base leads, though the one on a trip is more trusted")
	g.world.free()
	var g2 := _game()
	var sim2 = g2.sim
	for q in sim2.people:
		q.trust = 40.0
		if q != g2.p:
			q.away = {"kind": "party"}
	_person(sim2, "dez").trust = 95.0
	sim2.medical.kill(g2.p, "bled out")
	eq(sim2.player_id, "dez", "with nobody at home a party member out on a trip is in line")
	g2.world.free()


func test_a_turned_player_hands_over_too() -> void:
	var g := _game()
	var sim = g.sim
	sim.medical._turn(g.p)
	check(sim.player_id != "" and sim.player_id != "ruth", "the next in line: %s" % sim.player_id)
	check(not g.p.player, "the turned one is not the player")
	g.world.free()


func test_losing_the_player_shocks_everyones_morale_and_frees_the_new_players_post() -> void:
	var g := _game()
	var sim = g.sim
	sim.morale.enabled = true
	_person(sim, "ana").trust = 99.0
	sim.jobs.assign(_person(sim, "ana"), "infirmary")
	sim.medical.kill(g.p, "bled out")
	var found := false
	for entry in sim.morale.shocks.get("dez", []):
		if String(entry.label) == "Lost Ruth":
			found = true
			check(float(entry.value) < 0.0, "a loss")
	check(found, "Dez is shaken: 'Lost Ruth'")
	eq(sim.jobs.job_of(_person(sim, "ana")), "", "the new player has no station: the AI does not post them")
	g.world.free()


func test_the_new_player_starts_clean() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "dez")
	dez.trust = 99.0
	dez.stance = "follow"
	dez.stance_at = Vector2(3, 4)
	dez.drafted = true
	dez.order = Vector3(40, 30, 0)
	sim.medical.kill(g.p, "bled out")
	eq(sim.player_id, "dez", "Dez leads")
	eq(dez.stance, "", "a leader follows nobody")
	check(dez.order == null and not dez.drafted, "and has no orders of the AI")
	g.world.free()


func test_when_everyone_is_gone_there_is_no_successor_and_the_run_is_lost() -> void:
	var g := _game()
	var sim = g.sim
	for q in sim.people:
		if q != g.p:
			sim.medical.kill(q, "bled out")
	check(g.p.player, "the last one standing is still the player")
	sim.medical.kill(g.p, "bled out")
	sim.update(DT)
	eq(sim.over, "defeat", "the scenario ends as it always did")
	g.world.free()


func test_kill_and_turn_of_somebody_else_leave_the_player_alone() -> void:
	var g := _game()
	var sim = g.sim
	sim.medical.kill(_person(sim, "dez"), "bled out")
	eq(sim.player_id, "ruth", "still Ruth")
	near(_person(sim, "ana").trust, 55.0, 0.0001, "and trust is as it was")
	g.world.free()


# --------------------------------------------------------------- the AI gates --

func test_the_avatar_is_given_no_job_by_the_ai() -> void:
	var g := Helpers.make(3, 1, 6)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	eq(sim.jobs.job_of(ruth), "radio", "Ruth starts at the radio desk")
	sim.avatar.set_player(ruth)
	eq(sim.jobs.job_of(ruth), "", "the player leaves their station")
	sim.jobs.auto_assign()
	eq(sim.jobs.job_of(ruth), "", "and Auto-assign does not give them one")
	for q in sim.people:
		if q != ruth:
			check(sim.jobs.job_of(q) != "", "%s is placed" % q.id)
	g.world.free()


func test_the_ai_does_not_send_the_avatar_to_the_wall_or_to_the_sick() -> void:
	var g := _game()
	var sim = g.sim
	var p = g.p
	sim.tactics._send_to_the_wall(p, 2.0, {})
	check(p.repair == null, "no wall repair of the AI")
	p.skills["Medicine"] = 9
	check(not sim.medical._is_free(p), "not a free healer")
	check(not sim.medical._is_free_for_job(p), "nor one for a job")
	check(not sim.scavenge.can_go(p), "not for a party of the dice")
	check(not sim.scavenge._is_heading_out(p), "and not walked to the gate")
	check(not sim.jobs._able(p), "not a hand for a station")
	g.world.free()


func test_the_avatar_can_be_bitten_and_downed_like_anyone() -> void:
	var g := _game()
	var sim = g.sim
	var p = g.p
	var z = sim.spawn(p.x + 0.4, p.y, "breach")
	z.attack_t = 0.0
	var hp: float = p.hp
	_step(sim, 2.0)
	check(p.hp < hp, "bitten: %f" % p.hp)
	_step(sim, 25.0)
	check(p.downed, "and brought down in the end")
	g.world.free()


# ---------------------------------------------------------------------- saves --

func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func test_the_player_and_the_new_fields_survive_a_save_and_load() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "dez")
	dez.trust = 31.5
	dez.stance = "hold"
	dez.stance_at = Vector2(44.5, 28.5)
	sim.avatar.set_input(Vector2(1, 0), Vector2(46.5, 30.5), false)
	g.p.bloom = 0.4
	var text := SaveGame.to_text(SaveGame.to_dict(sim))
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(text)), "the save applies")
	eq(b.sim.player_id, "ruth", "the player")
	check(b.sim.avatar.player() == _person(b.sim, "ruth"), "player() finds them")
	check(_person(b.sim, "ruth").player, "flagged")
	var d2 = _person(b.sim, "dez")
	near(d2.trust, 31.5, 0.0001, "trust")
	eq(d2.stance, "hold", "the stance")
	eq(d2.stance_at, Vector2(44.5, 28.5), "and its spot")
	eq(_person(b.sim, "ruth").input_move, Vector2(1, 0), "the input")
	near(_person(b.sim, "ruth").bloom, 0.4, 0.0001, "the bloom")
	var n := 0
	for q in b.sim.people:
		if q.player:
			n += 1
	eq(n, 1, "one player")
	g.world.free()
	b.world.free()


func test_an_old_save_without_a_player_loads_with_the_defaults() -> void:
	var g := Helpers.make(5, 1, 6)
	Helpers.run(g.sim, 2.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(g.sim)))
	# as a save from before round 17: none of the new variables, and no avatar module
	d.modules.erase("avatar")
	for pd in d.people:
		for k in ["player", "input_move", "input_aim", "input_fire", "input_reload", "input_melee", "melee_t", "bloom", "trust", "stance", "stance_at"]:
			pd.erase(k)
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "it applies")
	eq(b.sim.player_id, "", "no avatar: the old game")
	for q in b.sim.people:
		check(not q.player, "%s is not the player" % q.id)
		near(q.trust, 55.0, 0.0001, "trust at its default")
		eq(q.stance, "", "no stance")
	g.world.free()
	b.world.free()


# ----------------------------------------------------------- in a played trip --

const W := 30
const H := 16


func _site() -> Dictionary:
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
		"containers": [],
		"dead": [], "rooms": [], "seed": 1,
	}


func _trip(dead: Array) -> Dictionary:
	var site := _site()
	site["dead"] = dead
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var g := Helpers.make(3, 1, 6)
	var members: Array = []
	for i in 2:
		var p = g.sim.people[i]
		members.append({"def": p.def, "hp": 100.0, "skills": p.skills})
	var run = RaidRun.new(site, world, FxNull.new(), members, 300.0, "", 1.0, false)
	return {"run": run, "world": world, "g": g}


func test_the_same_avatar_walks_and_shoots_in_a_place() -> void:
	var ctx := _trip([{"pos": Vector2(10.5, 8.5), "kind": "walker", "state": "still"}])
	var run = ctx.run
	var sim = run.sim
	var p = run.squad[0]
	p.weapon = "rifle"
	p.gun = sim.weapons.rifle
	p.mag = 20
	p.cooldown = 0.0
	check(sim.avatar.set_player(p), "the leader of the squad is the player")
	eq(sim.player_id, p.id, "in the place's own sim")
	run.squad[1].downed = true    # (the other one does not shoot: the shot is the avatar's)
	var z = sim.zombies[0]
	z.hp = 1.0
	var x0: float = p.x
	sim.avatar.set_input(Vector2(1, 0), Vector2(11.5, 8.5), false)
	for i in 30:
		run.update(DT)
	near(p.x - x0, 3.2, 0.1, "walks at the same speed in a place")
	# walled in by the house: the avatar keeps out of its wall
	sim.avatar.set_input(Vector2(1, 0), Vector2(11.5, 8.5), true)
	for i in 30:
		run.update(DT)
	check(z.state == "dying" or z.state == "dead", "and shoots the dead of the place: %s" % z.state)
	check(sim.stock.ammo < 300.0 and p.stats.shots >= 1, "from the trip's ammunition")
	eq(int(p.stats.kills), 1, "and is credited with it")
	ctx.world.free()
	ctx.g.world.free()


func test_a_wall_of_a_place_stops_the_avatar_and_its_shots() -> void:
	var ctx := _trip([{"pos": Vector2(20.5, 5.5), "kind": "walker", "state": "still"}])
	var run = ctx.run
	var sim = run.sim
	var p = run.squad[0]
	p.weapon = "rifle"
	p.gun = sim.weapons.rifle
	p.mag = 20
	p.cooldown = 0.0
	sim.avatar.set_player(p)
	run.squad[1].downed = true
	p.x = 10.5
	p.y = 5.5    # outside the house's west wall (x = 14), whose door is at (14, 8)
	var z = sim.zombies[0]
	z.hp = 1.0
	sim.avatar.set_input(Vector2(1, 0), Vector2(20.5, 5.5), true)
	for i in 120:
		run.update(DT)
	check(p.x < 14.0 - 0.29 + 0.01, "kept out by the wall: %f" % p.x)
	check(z.state != "dying" and z.state != "dead", "and the shots stopped by it")
	ctx.world.free()
	ctx.g.world.free()


func test_a_squad_mate_succeeds_in_a_place_when_the_avatar_falls() -> void:
	var ctx := _trip([])
	var run = ctx.run
	var sim = run.sim
	var a = run.squad[0]
	var b = run.squad[1]
	sim.avatar.set_player(a)
	a.hp = 0.0
	sim.medical.kill(a, "bled out")
	eq(sim.player_id, b.id, "the other one of the squad leads on")
	g_free(ctx)


func g_free(ctx: Dictionary) -> void:
	ctx.world.free()
	ctx.g.world.free()
